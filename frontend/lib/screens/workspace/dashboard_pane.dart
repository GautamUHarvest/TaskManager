import 'package:material_ui/material_ui.dart';

import '../../auth/auth_controller.dart';
import '../../common/widgets/future_view.dart';
import '../../common/widgets/pane_scaffold.dart';
import '../../tasks/task_models.dart';

/// Landing pane: headline task counts (each a shortcut into a list) and
/// quick actions.
class DashboardPane extends StatefulWidget {
  const DashboardPane({
    super.key,
    required this.controller,
    required this.onOpenCreate,
    required this.onOpenMine,
    required this.onOpenAll,
    required this.onOpenCompleted,
  });

  final AuthController controller;
  final VoidCallback onOpenCreate;
  final VoidCallback onOpenMine;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenCompleted;

  @override
  State<DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<DashboardPane> {
  late Future<List<Task>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.allTasks();
  }

  void _reload() => setState(() => _future = widget.controller.allTasks());

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.currentUser?.displayName;
    return PaneScaffold(
      title: name == null ? 'Dashboard' : 'Welcome, ${name.split(' ').first}',
      trailing: RefreshIconButton(onPressed: _reload),
      child: FutureView<List<Task>>(
        future: _future,
        onRetry: _reload,
        builder: (context, tasks) => ListView(
          children: [
            _buildStats(tasks),
            const SizedBox(height: 20),
            _QuickActionsCard(
              onOpenCreate: widget.onOpenCreate,
              onOpenMine: widget.onOpenMine,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(List<Task> tasks) {
    final myId = widget.controller.currentUser?.id;
    final counts = <TaskStatus, int>{};
    for (final task in tasks) {
      counts[task.status] = (counts[task.status] ?? 0) + 1;
    }
    final mine = tasks.where((task) => task.assigneeId == myId).length;
    String count(TaskStatus status) => '${counts[status] ?? 0}';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatTile(
          label: 'All tasks',
          value: '${tasks.length}',
          onTap: widget.onOpenAll,
        ),
        _StatTile(
          label: 'Assigned to me',
          value: '$mine',
          onTap: widget.onOpenMine,
        ),
        _StatTile(
          label: 'In progress',
          value: count(TaskStatus.inProgress),
          onTap: widget.onOpenAll,
        ),
        _StatTile(
          label: 'Blocked',
          value: count(TaskStatus.blocked),
          onTap: widget.onOpenAll,
        ),
        _StatTile(
          label: 'Done',
          value: count(TaskStatus.done),
          onTap: widget.onOpenCompleted,
        ),
      ],
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onOpenCreate,
    required this.onOpenMine,
  });

  final VoidCallback onOpenCreate;
  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onOpenCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('New Task'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenMine,
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('My Tasks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
