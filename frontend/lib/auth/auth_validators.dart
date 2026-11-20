// Client-side checks that mirror the backend's `security::valid*` rules and
// the SQLite triggers. They are a convenience only — the server re-validates —
// so keep them in sync when either side changes.

final RegExp _companyEmail =
    RegExp(r'^[A-Za-z0-9._+-]+@uharvest\.in$', caseSensitive: false);
final RegExp _employeeId = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// Only `@uharvest.in` addresses may register.
bool isValidCompanyEmail(String email) => _companyEmail.hasMatch(email);

/// 1–64 letters, digits, dots, underscores or hyphens.
bool isValidEmployeeId(String id) => _employeeId.hasMatch(id);

/// 6+ characters with an uppercase letter, a digit, and a symbol.
bool isValidPassword(String password) =>
    password.length >= 6 &&
    RegExp(r'[A-Z]').hasMatch(password) &&
    RegExp(r'[0-9]').hasMatch(password) &&
    RegExp(r'[^A-Za-z0-9]').hasMatch(password);
