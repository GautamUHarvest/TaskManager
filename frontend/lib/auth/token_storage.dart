// This app only ships to Flutter Web (see CLAUDE.md), so `dart:html` is the
// right fit for `window.localStorage`. The `package:web` migration can wait
// until the broader project moves off `dart:html`.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'auth_api.dart';

/// Persisted session payload: the signed-in user plus the refresh token.
/// SECURITY NOTE: the refresh token is stored in localStorage (readable by
/// JavaScript, XSS-exposed) — a deliberate tradeoff so the app works over plain
/// HTTP. [AuthController.restore] uses the token to get a fresh access token on
/// reload; if the server rejects it, the payload is wiped and the user signs in
/// again.
class PersistedSession {
  const PersistedSession({required this.user, required this.refreshToken});

  final AuthUser user;
  final String refreshToken;
}

/// LocalStorage-backed store for the signed-in user and their refresh token.
/// The refresh token is a secret held in plaintext here (see [PersistedSession]
/// security note); it is only acceptable for a LAN/demo deployment.
class TokenStorage {
  TokenStorage({String storageKey = _defaultKey}) : _key = storageKey;

  // v2: payload now carries the refresh token. A v1 entry (user only) is
  // silently ignored by read() — it lacks a refresh token — so old sessions
  // fall through to the sign-in screen.
  static const String _defaultKey = 'task_manager.session.v2';

  final String _key;

  PersistedSession? read() {
    final raw = html.window.localStorage[_key];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final userJson = decoded['user'];
      final refreshToken = decoded['refresh_token'];
      if (userJson is! Map<String, dynamic> ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        return null;
      }
      return PersistedSession(
        user: AuthUser.fromJson(userJson),
        refreshToken: refreshToken,
      );
    } catch (_) {
      // Corrupt payload — treat as absent so the user signs in again.
      clear();
      return null;
    }
  }

  void write({required AuthUser user, required String refreshToken}) {
    html.window.localStorage[_key] = jsonEncode({
      'user': {
        'id': user.id,
        'employee_id': user.employeeId,
        'email': user.email,
        'display_name': user.displayName,
      },
      'refresh_token': refreshToken,
    });
  }

  void clear() {
    html.window.localStorage.remove(_key);
  }
}
