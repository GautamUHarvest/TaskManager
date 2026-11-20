import 'package:material_ui/material_ui.dart';

import '../task_models.dart';

/// Title rule shared by every task form: required, at most 200 characters.
String? validateTaskTitle(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter a title';
  if (text.length > 200) return 'Title must be 200 characters or fewer';
  return null;
}

class TaskTitleField extends StatelessWidget {
  const TaskTitleField({
    super.key,
    required this.controller,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      decoration: const InputDecoration(labelText: 'Title'),
      validator: validateTaskTitle,
    );
  }
}

class TaskDescriptionField extends StatelessWidget {
  const TaskDescriptionField({
    super.key,
    required this.controller,
    this.minLines = 2,
    this.maxLines = 4,
  });

  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: 4000,
      decoration: const InputDecoration(labelText: 'Description (optional)'),
    );
  }
}

/// A dropdown over a fixed set of values (typically an enum), labelled by
/// [itemLabel]. Ignores a null selection, since every value is valid.
class ChoiceDropdownField<T> extends StatelessWidget {
  const ChoiceDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

/// The Status / Type / Discipline dropdown trio every task form carries.
class TaskClassificationFields extends StatelessWidget {
  const TaskClassificationFields({
    super.key,
    required this.status,
    required this.type,
    required this.discipline,
    required this.onStatusChanged,
    required this.onTypeChanged,
    required this.onDisciplineChanged,
  });

  final TaskStatus status;
  final TaskType type;
  final TaskDiscipline discipline;
  final ValueChanged<TaskStatus> onStatusChanged;
  final ValueChanged<TaskType> onTypeChanged;
  final ValueChanged<TaskDiscipline> onDisciplineChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceDropdownField<TaskStatus>(
          label: 'Status',
          value: status,
          values: TaskStatus.values,
          itemLabel: (status) => status.label,
          onChanged: onStatusChanged,
        ),
        const SizedBox(height: 16),
        ChoiceDropdownField<TaskType>(
          label: 'Type',
          value: type,
          values: TaskType.values,
          itemLabel: (type) => type.label,
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 16),
        ChoiceDropdownField<TaskDiscipline>(
          label: 'Discipline',
          value: discipline,
          values: TaskDiscipline.values,
          itemLabel: (discipline) => discipline.label,
          onChanged: onDisciplineChanged,
        ),
      ],
    );
  }
}
