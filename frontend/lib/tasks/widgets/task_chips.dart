import 'package:material_ui/material_ui.dart';

import '../task_models.dart';

/// A small, neutral tag for secondary attributes like type and discipline.
/// Deliberately low-contrast so it doesn't compete with the status chip.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A rounded, color-coded chip for a [TaskStatus]. Colors come from the
/// Material 3 scheme so it reads correctly in light and dark themes.
class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({super.key, required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color background;
    late final Color foreground;
    Color? border;
    switch (status) {
      case TaskStatus.todo:
        background = scheme.surface;
        foreground = scheme.onSurfaceVariant;
        border = scheme.outline;
      case TaskStatus.inProgress:
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
      case TaskStatus.blocked:
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
      case TaskStatus.done:
        background = scheme.secondaryContainer;
        foreground = scheme.onSecondaryContainer;
      case TaskStatus.cancelled:
        background = scheme.surface;
        foreground = scheme.onSurfaceVariant;
        border = scheme.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A task's position in its project ("#21"), shown before the title so list
/// order and the planning sheet's numbering can be matched at a glance.
class TaskIndexBadge extends StatelessWidget {
  const TaskIndexBadge({super.key, required this.index, this.large = false});

  final int index;

  /// Sized for the task-detail heading instead of a list row.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 8,
        vertical: large ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '#$index',
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: large ? 18 : 13,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
