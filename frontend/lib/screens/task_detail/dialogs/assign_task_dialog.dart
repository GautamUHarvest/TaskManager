import 'package:material_ui/material_ui.dart';

import '../../../auth/auth_api.dart';
import '../../../auth/auth_controller.dart';
import '../../../common/submit_state.dart';
import '../../../common/widgets/form_dialog.dart';
import '../../../tasks/task_models.dart';
import '../../../tasks/widgets/assignee_picker_field.dart';

/// Change who a task is assigned to. Any member may do this, so it sends
/// only `assignee_ids` — the server rejects other fields from non-editors.
/// Pops the server's updated [Task] on save, null on cancel.
class AssignTaskDialog extends StatefulWidget {
  const AssignTaskDialog({
    super.key,
    required this.controller,
    required this.task,
    required this.users,
  });

  final AuthController controller;
  final Task task;
  final List<AuthUser> users;

  @override
  State<AssignTaskDialog> createState() => _AssignTaskDialogState();
}

class _AssignTaskDialogState extends State<AssignTaskDialog>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  late List<int> _assigneeIds;

  @override
  void initState() {
    super.initState();
    _assigneeIds = [...widget.task.allAssigneeIds];
  }

  Future<void> _submit() async {
    await runSubmit(() async {
      final updated = await widget.controller.updateTask(
        taskId: widget.task.id,
        assigneeIds: _assigneeIds,
      );
      if (mounted) Navigator.pop(context, updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Assign task',
      formKey: _formKey,
      width: 460,
      busy: submitting,
      error: submitError,
      submitLabel: 'Save',
      onSubmit: _submit,
      children: [
        AssigneePickerField(
          users: widget.users,
          selectedIds: _assigneeIds,
          onChanged: (ids) => setState(() => _assigneeIds = ids),
        ),
      ],
    );
  }
}
