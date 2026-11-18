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
