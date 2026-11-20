import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';
import '../../common/widgets/muted_text.dart';
import '../../common/widgets/section_card.dart';
import '../../tasks/task_models.dart';
import '../../tasks/widgets/task_chips.dart';

/// The task's direct children, each opening its own detail screen.
class SubtasksSection extends StatelessWidget {
  const SubtasksSection({
    super.key,
    required this.subtasks,
    required this.canAdd,
    required this.onAdd,
    required this.onOpen,
    required this.assigneeLabel,
  });

  final List<Task> subtasks;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<Task> onOpen;
  final String Function(int? userId) assigneeLabel;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Subtasks (${subtasks.length})',
      trailing: canAdd
          ? FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add subtask'),
            )
          : null,
      children: [
        if (subtasks.isEmpty)
          MutedText(
            canAdd
                ? 'No subtasks yet. Break this down with "Add subtask".'
                : 'No subtasks yet.',
          )
        else
          for (final subtask in subtasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SubtaskTile(
                subtask: subtask,
                assigneeLabel: assigneeLabel(subtask.assigneeId),
                onTap: () => onOpen(subtask),
              ),
            ),
      ],
    );
  }
}

class _SubtaskTile extends StatelessWidget {
  const _SubtaskTile({
    required this.subtask,
    required this.assigneeLabel,
    required this.onTap,
  });

  final Task subtask;
  final String assigneeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showType = subtask.type != TaskType.decide;
    final showDiscipline = subtask.discipline != TaskDiscipline.decide;
    final dueAt = subtask.dueAt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtask.title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  MutedText(assigneeLabel, style: theme.textTheme.bodySmall),
                  if (showType || showDiscipline || dueAt != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (showType) TagChip(label: subtask.type.label),
                        if (showDiscipline)
                          TagChip(label: subtask.discipline.label),
                        if (dueAt != null)
                          TagChip(label: 'Due ${formatDate(dueAt)}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            TaskStatusChip(status: subtask.status),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
