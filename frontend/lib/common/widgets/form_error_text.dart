import 'package:material_ui/material_ui.dart';

/// Inline error line shown under a form after a failed submit.
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key, this.textAlign});

  final String message;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: textAlign,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
