import 'package:material_ui/material_ui.dart';

import '../../../tasks/task_models.dart';

/// Lets the user pick a [TaskStatus], marking [current]. Resolves to the
/// chosen status, or null when dismissed.
Future<TaskStatus?> showStatusPicker(
  BuildContext context, {
  required TaskStatus current,
}) {
  return showDialog<TaskStatus>(
    context: context,
    builder: (context) {
      final primary = Theme.of(context).colorScheme.primary;
      return SimpleDialog(
        title: const Text('Change status'),
        children: [
          for (final status in TaskStatus.values)
            ListTile(
              leading: Icon(
                status == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: status == current ? primary : null,
              ),
              title: Text(status.label),
              onTap: () => Navigator.pop(context, status),
            ),
        ],
      );
    },
  );
}
