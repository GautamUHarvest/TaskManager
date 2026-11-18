import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.employeeId,
    required this.email,
    required this.displayName,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        employeeId: json['employee_id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
      );

  final int id;
  final String employeeId;
  final String email;
  final String displayName;
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final AuthUser user;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'API_BASE_URL',
                  defaultValue: 'https://localhost:5555',
                ))
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<void> register({
    required String employeeId,
    required String email,
    required String displayName,
    required String password,
  }) async {
    await _post('/api/auth/register', {
      'employee_id': employeeId,
      'email': email,
      'display_name': displayName,
      'password': password,
    });
  }

  Future<AuthTokens> login(String login, String password) async {
    final json = await _post('/api/auth/login', {
      'login': login,
      'password': password,
    });
    return AuthTokens.fromJson(json);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _post('/api/auth/refresh', {
      'refresh_token': refreshToken,
    });
    return AuthTokens.fromJson(json);
  }

  Future<AuthUser> profile(String accessToken) async {
    final response = await _client.get(
      _uri('/api/auth/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final json = _decodeResponse(response);
    return AuthUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> logout(String accessToken) async {
    final response = await _client.post(
      _uri('/api/auth/logout'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 204) {
      _decodeResponse(response);
    }
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
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
}
