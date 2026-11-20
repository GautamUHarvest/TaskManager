import 'package:material_ui/material_ui.dart';

extension SnackBarContext on BuildContext {
  /// Shows a plain one-line snackbar on the nearest [ScaffoldMessenger].
  void showSnackMessage(String message) {
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(message)));
  }
}
