import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Base URL baked in at build time via `--dart-define=API_BASE_URL=...`.
/// Defaults to `/api` so a production build served behind nginx is same-origin.
const String kApiBaseUrlFromEnv =
    String.fromEnvironment('API_BASE_URL', defaultValue: '/api');

String normalizeBaseUrl(String? baseUrl) =>
    (baseUrl ?? kApiBaseUrlFromEnv).replaceFirst(RegExp(r'/$'), '');

/// Thrown for any non-2xx response. [message] comes from the backend's
/// `{ "error": "..." }` shape; [statusCode] drives the 401 refresh retry.
class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Decodes a JSON response, mapping the backend error shape to
/// [AuthApiException]. Returns an empty map for empty bodies (e.g. 204).
Map<String, dynamic> decodeApiResponse(http.Response response) {
  Map<String, dynamic> json = const {};
  if (response.body.isNotEmpty) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } on FormatException {
      throw AuthApiException(
        'The server returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw AuthApiException(
      json['error'] as String? ?? 'Request failed (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }
  return json;
}

/// Thin HTTP layer shared by [AuthApi] and the data APIs. Handles the base
/// URL, JSON encoding, optional Bearer auth, and error decoding in one place.
///
/// Default client is a [BrowserClient] with `withCredentials = true` so the
/// browser sends and accepts the HttpOnly `refresh_token` cookie on
/// `/api/auth/*` requests. Without this, cross-origin dev
/// (`http://localhost:5000` → `https://localhost:5555`) would silently drop
/// the cookie and refresh would fail with 401.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? (BrowserClient()..withCredentials = true),
        _baseUrl = normalizeBaseUrl(baseUrl);

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers({String? token, bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> post(
    String path,
    Object body, {
    String? token,
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers(token: token, json: true),
      body: jsonEncode(body),
    );
    return decodeApiResponse(response);
  }

  /// GET a JSON resource. [noCache] appends a unique query parameter so the
  /// browser (on Flutter Web, `http` goes through fetch/XHR, which honors the
  /// HTTP cache) cannot serve a stale response for a URL we just mutated —
  /// e.g. re-fetching `/task/detail` right after posting a note. We bust the
  /// cache with a query param rather than a `Cache-Control` header to avoid a
  /// CORS preflight against the backend's exact-origin allowlist.
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    bool noCache = false,
  }) async {
    final effectivePath = noCache
        ? '$path${path.contains('?') ? '&' : '?'}'
            '_=${DateTime.now().microsecondsSinceEpoch}'
        : path;
    final response = await _client.get(
      _uri(effectivePath),
      headers: _headers(token: token),
    );
    return decodeApiResponse(response);
  }

  /// POST with no body, tolerating a `204 No Content` success.
  Future<void> postEmpty(String path, {String? token}) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers(token: token),
    );
    if (response.statusCode != 204) {
      decodeApiResponse(response);
    }
  }
}
