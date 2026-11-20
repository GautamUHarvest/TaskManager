import 'package:material_ui/material_ui.dart';

/// Puts a thin progress bar above [child] while [refreshing], so a
/// background refetch is visible without blanking content already on screen.
/// The bar's slot is always reserved, so the content never jumps.
class RefreshingColumn extends StatelessWidget {
  const RefreshingColumn({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 3,
          child: refreshing ? const LinearProgressIndicator() : null,
        ),
        Expanded(child: child),
      ],
    );
  }
}
