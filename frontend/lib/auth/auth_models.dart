// Auth wire models. Kept free of any transport import so domain helpers and
// unit tests can use them without pulling in the browser HTTP client.

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
