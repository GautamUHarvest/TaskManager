import 'package:material_ui/material_ui.dart';

import '../../../auth/auth_api.dart';
import '../../../auth/auth_controller.dart';
import '../../../common/submit_state.dart';
import '../../../common/widgets/form_dialog.dart';
import '../../../tasks/task_models.dart';
import '../../../tasks/widgets/task_date_fields.dart';
import '../../../tasks/widgets/task_form_fields.dart';

/// Creates a subtask under [parent]. Pops true when one was created, false
/// on cancel.
class AddSubtaskDialog extends StatefulWidget {
  const AddSubtaskDialog({
    super.key,
    required this.controller,
    required this.parent,
    required this.users,
  });

  final AuthController controller;
  final Task parent;
  final List<AuthUser> users;

  @override
  State<AddSubtaskDialog> createState() => _AddSubtaskDialogState();
}

class _AddSubtaskDialogState extends State<AddSubtaskDialog>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  TaskStatus _status = TaskStatus.todo;
  TaskType _type = TaskType.decide;
  TaskDiscipline _discipline = TaskDiscipline.decide;
  int? _assigneeId;
  DateTime? _startDate;
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final assigneeId = _assigneeId;
    await runSubmit(() async {
      await widget.controller.createSubtask(
        parentTaskId: widget.parent.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
        type: _type,
        discipline: _discipline,
        startAt: _startDate,
        dueAt: _dueDate,
        assigneeIds: assigneeId == null ? const [] : [assigneeId],
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Add subtask',
      formKey: _formKey,
      busy: submitting,
      error: submitError,
      submitLabel: 'Create',
      cancelResult: false,
      onSubmit: _submit,
      children: [
        TaskTitleField(controller: _titleController, autofocus: true),
        const SizedBox(height: 16),
        TaskDescriptionField(controller: _descriptionController),
        const SizedBox(height: 8),
        TaskClassificationFields(
          status: _status,
          type: _type,
          discipline: _discipline,
          onStatusChanged: (value) => setState(() => _status = value),
          onTypeChanged: (value) => setState(() => _type = value),
          onDisciplineChanged: (value) => setState(() => _discipline = value),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int?>(
          initialValue: _assigneeId,
          decoration: const InputDecoration(labelText: 'Assign to'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Unassigned'),
            ),
            for (final user in widget.users)
              DropdownMenuItem<int?>(
                value: user.id,
                child: Text(user.displayName),
              ),
          ],
          onChanged: (value) => setState(() => _assigneeId = value),
        ),
        const SizedBox(height: 16),
        TaskDateFields(
          startDate: _startDate,
          dueDate: _dueDate,
          onChanged: (start, due) => setState(() {
            _startDate = start;
            _dueDate = due;
          }),
        ),
      ],
    );
  }
}
