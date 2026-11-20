import 'package:material_ui/material_ui.dart';

/// Circle avatar showing the first letter of [name] ("?" when empty), in
/// the theme's primary-container colors.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    this.radius,
    this.textStyle,
  });

  final String name;
  final double? radius;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: textStyle,
      ),
    );
  }
}
