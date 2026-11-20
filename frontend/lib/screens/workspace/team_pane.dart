import 'package:material_ui/material_ui.dart';

import '../../auth/auth_api.dart';
import '../../auth/auth_controller.dart';
import '../../common/widgets/future_view.dart';
import '../../common/widgets/initial_avatar.dart';
import '../../common/widgets/message_card.dart';
import '../../common/widgets/pane_scaffold.dart';

/// The team directory: every registered member.
class TeamPane extends StatefulWidget {
  const TeamPane({super.key, required this.controller});

  final AuthController controller;

  @override
  State<TeamPane> createState() => _TeamPaneState();
}

class _TeamPaneState extends State<TeamPane> {
  late Future<List<AuthUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.allUsers();
  }

  void _reload() => setState(() => _future = widget.controller.allUsers());

  @override
  Widget build(BuildContext context) {
    return PaneScaffold(
      title: 'Team',
      trailing: RefreshIconButton(onPressed: _reload),
      child: FutureView<List<AuthUser>>(
        future: _future,
        onRetry: _reload,
        builder: (context, users) {
          if (users.isEmpty) {
            return const MessageListView(message: 'No team members found.');
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: InitialAvatar(name: user.displayName),
                title: Text(user.displayName),
                subtitle: Text('${user.employeeId} · ${user.email}'),
              );
            },
          );
        },
      ),
    );
  }
}
