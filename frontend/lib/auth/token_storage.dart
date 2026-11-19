// This app only ships to Flutter Web (see CLAUDE.md), so `dart:html` is the
// right fit for `window.localStorage`. The `package:web` migration can wait
// until the broader project moves off `dart:html`.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'auth_api.dart';

/// Cached-user payload. The refresh token is NOT here — it lives in an
/// HttpOnly cookie the browser handles automatically. This cache exists only
/// so the signed-in shell can paint immediately on reload while
/// [AuthController.restore] calls `/auth/refresh` in the background. If the
/// cookie turns out to be dead, the cache is wiped and the user signs in
/// again.
class PersistedSession {
  const PersistedSession({required this.user});

  final AuthUser user;
}

/// LocalStorage-backed cache of the last signed-in user. Holds no secrets —
/// the refresh token is a server-set HttpOnly cookie that JavaScript cannot
/// read or write.
class TokenStorage {
  TokenStorage({String storageKey = _defaultKey}) : _key = storageKey;

  static const String _defaultKey = 'task_manager.session.v1';

  final String _key;

  PersistedSession? read() {
    final raw = html.window.localStorage[_key];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final userJson = decoded['user'];
      if (userJson is! Map<String, dynamic>) return null;
      return PersistedSession(user: AuthUser.fromJson(userJson));
    } catch (_) {
      // Corrupt payload — treat as absent so the user signs in again.
      clear();
      return null;
    }
  }

  void write({required AuthUser user}) {
    html.window.localStorage[_key] = jsonEncode({
      'user': {
        'id': user.id,
        'employee_id': user.employeeId,
        'email': user.email,
        'display_name': user.displayName,
      },
    });
  }

  void clear() {
    html.window.localStorage.remove(_key);
  }
}
