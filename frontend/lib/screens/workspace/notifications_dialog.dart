import 'package:material_ui/material_ui.dart';

import '../../auth/auth_controller.dart';
import '../../common/date_format.dart';
import '../../common/error_messages.dart';
import '../../tasks/task_models.dart';

/// Lists the user's notifications and marks the fetched ones read, so they
/// drop off later reads and the bell's badge count.
class NotificationsDialog extends StatefulWidget {
  const NotificationsDialog({super.key, required this.controller});

  final AuthController controller;

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  late final Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.notifications().then((items) {
      widget.controller.markNotificationsRead(items.map((item) => item.id));
      return items;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notifications'),
      content: SizedBox(
        width: 400,
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(errorMessage(snapshot.error));
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const Text('You have no notifications.');
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.isRead
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(item.message),
                    subtitle: item.createdAt == null
                        ? null
                        : Text(formatDate(item.createdAt!)),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
