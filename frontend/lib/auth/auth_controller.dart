import 'package:flutter/foundation.dart';

import 'auth_api.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.api);

  final AuthApi api;

  AuthTokens? _tokens;
  DateTime? _accessExpiresAt;

  bool get isAuthenticated => _tokens != null;

  Future<void> register({
    required String employeeId,
    required String email,
    required String displayName,
    required String password,
  }) =>
      api.register(
        employeeId: employeeId,
        email: email,
        displayName: displayName,
        password: password,
      );

  Future<void> login(String login, String password) async {
    _setTokens(await api.login(login, password));
  }

  Future<AuthUser> loadProfile() async {
    await _refreshIfExpiring();
    try {
      return await api.profile(_requireTokens().accessToken);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      await _refresh();
      return api.profile(_requireTokens().accessToken);
    }
  }

  Future<void> logout() async {
    await _refreshIfExpiring();
    await api.logout(_requireTokens().accessToken);
    _clearTokens();
  }

  Future<void> _refreshIfExpiring() async {
    if (_accessExpiresAt == null ||
        _accessExpiresAt!.isBefore(
          DateTime.now().add(const Duration(seconds: 30)),
        )) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final current = _requireTokens();
    _setTokens(await api.refresh(current.refreshToken));
  }

  AuthTokens _requireTokens() {
    final tokens = _tokens;
    if (tokens == null) {
      throw const AuthApiException('Your session has ended. Please sign in.');
    }
    return tokens;
  }

  void _setTokens(AuthTokens tokens) {
    _tokens = tokens;
    _accessExpiresAt =
        DateTime.now().add(Duration(seconds: tokens.expiresIn));
    notifyListeners();
  }

  void _clearTokens() {
    _tokens = null;
    _accessExpiresAt = null;
    notifyListeners();
  }
}
