import 'package:material_ui/material_ui.dart';

import 'button_spinner.dart';
import 'form_error_text.dart';

/// Frame shared by every create/edit dialog: a scrollable [Form] of
/// [children] at a fixed width, an inline [error] line under the fields, and
/// Cancel / submit actions that are disabled while [busy] (the submit button
/// swaps its label for a spinner).
///
/// The dialog's state (controllers, validation, the request itself) stays
/// with the caller; this only owns the layout.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    required this.busy,
    this.error,
    this.icon,
    this.width = 420,
    this.cancelResult,
    this.destructive = false,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool busy;
  final String? error;
  final Widget? icon;
  final double width;

  /// Value popped by Cancel (null by default).
  final Object? cancelResult;

  /// Paints the submit button in the error color.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: icon,
      title: Text(title),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 12),
                  FormErrorText(error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, cancelResult),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: busy ? null : onSubmit,
          child: busy ? const ButtonSpinner() : Text(submitLabel),
        ),
      ],
    );
  }
}
