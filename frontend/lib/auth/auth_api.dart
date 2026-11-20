import '../api/api_client.dart';
import 'auth_models.dart';

// Keep `AuthApiException` and the auth models importable via this file for
// existing call sites.
export '../api/api_client.dart' show AuthApiException;
export 'auth_models.dart';

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
