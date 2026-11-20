import 'package:material_ui/material_ui.dart';

/// A card holding a single message (empty state or error) with an optional
/// action underneath.
class MessageCard extends StatelessWidget {
  const MessageCard({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// [MessageCard] centered on the page with a readable max width. Used when
/// a full screen has nothing else to show.
class CenteredMessageCard extends StatelessWidget {
  const CenteredMessageCard({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MessageCard(message: message, action: action),
      ),
    );
  }
}

/// A [MessageCard] inside a scrollable list, so a pane's empty/error state
/// scrolls the same way its data does. Shows a "Try again" button when
/// [onRetry] is given.
class MessageListView extends StatelessWidget {
  const MessageListView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        MessageCard(
          message: message,
          action: onRetry == null ? null : RetryButton(onPressed: onRetry!),
        ),
      ],
    );
  }
}

/// The standard "Try again" button for a failed load.
class RetryButton extends StatelessWidget {
  const RetryButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(onPressed: onPressed, child: const Text('Try again'));
  }
}
