import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';
import '../../tasks/task_models.dart';
import '../../tasks/widgets/task_chips.dart';

/// One task row in a workspace list: title + status, a two-line description
/// preview, project / type / discipline tags, and people + date metadata.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.assigneesLabel,
    required this.createdByLabel,
    required this.projectName,
    required this.onTap,
  });

  final Task task;
  final String assigneesLabel;
  final String createdByLabel;
  final String? projectName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = task.description;
    final showType = task.type != TaskType.decide;
    final showDiscipline = task.discipline != TaskDiscipline.decide;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TaskStatusChip(status: task.status),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Project is always shown when known so the task's "home" is
              // visible at a glance; type/discipline only when decided.
              if (projectName != null || showType || showDiscipline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (projectName != null)
                        TagChip(label: 'Project: $projectName'),
                      if (showType) TagChip(label: task.type.label),
                      if (showDiscipline) TagChip(label: task.discipline.label),
                    ],
                  ),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _MetaChip(icon: Icons.person_outline, label: assigneesLabel),
                  _MetaChip(
                    icon: Icons.badge_outlined,
                    label: 'By $createdByLabel',
                  ),
                  if (task.startAt != null)
                    _MetaChip(
                      icon: Icons.play_circle_outline,
                      label: 'Starts ${formatDate(task.startAt!)}',
                    ),
                  if (task.dueAt != null)
                    _MetaChip(
                      icon: Icons.event_outlined,
                      label: 'Due ${formatDate(task.dueAt!)}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
