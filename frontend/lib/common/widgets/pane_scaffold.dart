import 'package:material_ui/material_ui.dart';

/// Shared page frame for a workspace pane: a title row with an optional
/// trailing action above the pane body, centered with a max width.
class PaneScaffold extends StatelessWidget {
  const PaneScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.maxWidth = 920,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// The standard "Refresh" icon button used in pane headers and app bars.
class RefreshIconButton extends StatelessWidget {
  const RefreshIconButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh',
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
    );
  }
}
