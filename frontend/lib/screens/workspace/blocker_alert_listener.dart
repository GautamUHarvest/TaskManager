import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../auth/auth_controller.dart';
import '../../common/date_format.dart';
import '../../common/widgets/muted_text.dart';
import '../../tasks/task_models.dart';

/// Listens to [AuthController.blockerAlerts] and presents each alert as a
/// modal, one at a time, above [child].
///
/// Each alert is acknowledged server-side only after the user taps OK, so a
/// flurry of them cannot stack dialogs on top of each other or be dismissed
/// unseen. If that acknowledgement fails the alert simply replays on the next
/// connect, which is the safe direction to fail in.
class BlockerAlertListener extends StatefulWidget {
  const BlockerAlertListener({
    super.key,
    required this.controller,
    required this.raisedByLabel,
    required this.onAlertHandled,
    required this.child,
  });

  final AuthController controller;

  /// Names the member who raised the blocker, from their user id.
  final String Function(int? userId) raisedByLabel;

  /// Called after each alert is dismissed — a blocker moves the task to
  /// "blocked", so counts shown elsewhere may have changed.
  final VoidCallback onAlertHandled;

  final Widget child;

  @override
  State<BlockerAlertListener> createState() => _BlockerAlertListenerState();
}

class _BlockerAlertListenerState extends State<BlockerAlertListener> {
  StreamSubscription<BlockerAlert>? _subscription;
  final List<BlockerAlert> _queue = <BlockerAlert>[];
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.blockerAlerts.listen((alert) {
      _queue.add(alert);
      _drainQueue();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _drainQueue() async {
    if (_showing) return;
    _showing = true;
    try {
      while (mounted && _queue.isNotEmpty) {
        final alert = _queue.removeAt(0);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => BlockerAlertDialog(
            alert: alert,
            raisedByLabel: widget.raisedByLabel(alert.notification.actorId),
          ),
        );
        if (!mounted) return;
        try {
          await widget.controller.acknowledgeBlocker(alert.id);
        } catch (_) {
          // Left unacknowledged on purpose — better shown twice than lost.
        }
        if (!mounted) return;
        widget.onAlertHandled();
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The blocker alert itself: someone has flagged this user as holding up a
/// task. Deliberately inescapable — `barrierDismissible: false` (set by the
/// caller) blocks a tap outside and the [PopScope] blocks Escape / browser
/// back — so it stays on screen until OK is tapped.
class BlockerAlertDialog extends StatelessWidget {
  const BlockerAlertDialog({
    super.key,
    required this.alert,
    required this.raisedByLabel,
  });

  final BlockerAlert alert;
  final String raisedByLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskTitle = alert.task?.title;
    final raisedAt = alert.notification.createdAt;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.report_problem_outlined, color: theme.colorScheme.error),
        title: const Text("You're blocking a task"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (taskTitle != null) ...[
                Text(
                  taskTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(alert.message, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 12),
              MutedText(
                'Raised by $raisedByLabel',
                style: theme.textTheme.bodySmall,
              ),
              if (raisedAt != null)
                MutedText(formatDate(raisedAt), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
