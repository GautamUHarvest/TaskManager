import 'package:material_ui/material_ui.dart';

import '../error_messages.dart';
import 'message_card.dart';

/// Renders [future] with the app's standard states: a spinner while waiting,
/// an error card with "Try again" (calling [onRetry]) on failure, and
/// [builder] once data arrives.
///
/// Blanks to the spinner on every reload. Panes that must keep their rows
/// visible through a refresh manage their own cache instead.
class FutureView<T> extends StatelessWidget {
  const FutureView({
    super.key,
    required this.future,
    required this.onRetry,
    required this.builder,
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return MessageListView(
            message: errorMessage(snapshot.error),
            onRetry: onRetry,
          );
        }
        return builder(context, snapshot.requireData);
      },
    );
  }
}
