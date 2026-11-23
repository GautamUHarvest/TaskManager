import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';
import '../../common/widgets/owner_actions_menu.dart';
import '../../tasks/task_models.dart';
import '../../tasks/task_permissions.dart';
import '../../tasks/widgets/task_chips.dart';

/// Top card of the task detail screen: title, owner menu, status and tags,
/// the actions the user is allowed, description, and people/date metadata.
class TaskHeaderCard extends StatelessWidget {
  const TaskHeaderCard({
    super.key,
    required this.task,
    required this.permissions,
    required this.assigneeLabel,
    required this.createdByLabel,
    required this.projectName,
    required this.onChangeStatus,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onRaiseBlocker,
  });

  final Task task;
  final TaskPermissions permissions;
  final String assigneeLabel;
  final String createdByLabel;
  final String? projectName;
  final VoidCallback onChangeStatus;
  final VoidCallback onEditTask;
  final VoidCallback onDeleteTask;
  final VoidCallback onRaiseBlocker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = task.description;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.index != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: TaskIndexBadge(index: task.index!, large: true),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                OwnerActionsMenu(
                  canEdit: permissions.canEdit,
                  canDelete: permissions.canDelete,
                  onEdit: onEditTask,
                  onDelete: onDeleteTask,
                  tooltip: 'Task actions',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TaskStatusChip(status: task.status),
                if (projectName != null)
                  TagChip(label: 'Project: $projectName'),
                TagChip(label: 'Type: ${task.type.label}'),
                TagChip(label: 'Discipline: ${task.discipline.label}'),
                // Status changes and blockers follow the same rule as
                // editing: creator or assignee.
                if (permissions.canEdit) ...[
                  OutlinedButton.icon(
                    onPressed: onChangeStatus,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Change status'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRaiseBlocker,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: const Text('Blocker'),
                  ),
                ],
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(description, style: theme.textTheme.bodyLarge),
            ],
            const Divider(height: 32),
            _MetaRow(
              icon: Icons.person_outline,
              label: 'Assigned to',
              value: assigneeLabel,
            ),
            const SizedBox(height: 10),
            _MetaRow(
              icon: Icons.badge_outlined,
              label: 'Assigned by',
              value: createdByLabel,
            ),
            if (task.startAt != null) ...[
              const SizedBox(height: 10),
              _MetaRow(
                icon: Icons.play_circle_outline,
                label: 'Starts',
                value: formatDate(task.startAt!),
              ),
            ],
            if (task.dueAt != null) ...[
              const SizedBox(height: 10),
              _MetaRow(
                icon: Icons.event_outlined,
                label: 'Due',
                value: formatDate(task.dueAt!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: Text(label, style: TextStyle(color: muted, fontSize: 13)),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
