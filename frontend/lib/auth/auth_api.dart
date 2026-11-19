import '../api/api_client.dart';

// Keep `AuthApiException` importable via this file for existing call sites.
export '../api/api_client.dart' show AuthApiException;

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

/// Login/refresh response payload. The refresh token **is** here — it is
/// returned in the JSON body, persisted to localStorage, and sent back in the
/// `/auth/refresh` request body. SECURITY NOTE: storing the refresh token in
/// localStorage makes it readable by JavaScript (XSS-exposed); this is a
/// deliberate tradeoff so the app works over plain HTTP on a LAN/demo box.
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
  AuthApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<void> register({
    required String employeeId,
    required String email,
    required String displayName,
    required String password,
  }) async {
    await _client.post('/auth/register', {
      'employee_id': employeeId,
      'email': email,
      'display_name': displayName,
      'password': password,
    });
  }

  Future<AuthTokens> login(String login, String password) async {
    final json = await _client.post('/auth/login', {
      'login': login,
      'password': password,
    });
    return AuthTokens.fromJson(json);
  }

  /// Exchanges the stored [refreshToken] for a new access token. The refresh
  /// token rotates on every call, so the caller must persist the new one from
  /// the returned [AuthTokens] in place of the one it sent.
  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _client.post('/auth/refresh', {
      'refresh_token': refreshToken,
    });
    return AuthTokens.fromJson(json);
  }

  Future<AuthUser> profile(String accessToken) async {
    final json = await _client.get('/auth/me', token: accessToken);
    return AuthUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> logout(String accessToken) async {
    await _client.postEmpty('/auth/logout', token: accessToken);
  }
}
