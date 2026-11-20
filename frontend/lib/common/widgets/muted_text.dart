import 'package:material_ui/material_ui.dart';

/// Secondary, low-emphasis text (empty states, hints, timestamps) in the
/// theme's `onSurfaceVariant` color. Defaults to `bodyMedium`; pass [style]
/// to start from a different text style.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium;
    return Text(
      text,
      style: base?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
