import 'package:material_ui/material_ui.dart';

import '../../../auth/auth_api.dart';
import '../../../auth/auth_controller.dart';
import '../../../common/submit_state.dart';
import '../../../common/widgets/form_dialog.dart';
import '../../../common/widgets/muted_text.dart';
import '../../../tasks/task_models.dart';
import '../../../tasks/widgets/task_date_fields.dart';
import '../../../tasks/widgets/task_form_fields.dart';

/// Edit an existing task. Pre-filled from [task]; the form submits every
/// field it manages, and emptying an optional one sends an explicit null so
/// the server clears it. Pops the server's updated [Task] on save, null on
/// cancel.
class EditTaskDialog extends StatefulWidget {
  const EditTaskDialog({
    super.key,
    required this.controller,
    required this.task,
    required this.users,
    required this.projects,
  });

  final AuthController controller;
  final Task task;
  final List<AuthUser> users;
  final List<Project> projects;

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late TaskStatus _status;
  late TaskType _type;
  late TaskDiscipline _discipline;
  late final Set<int> _assigneeIds;
  late int? _projectId;
  DateTime? _startDate;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task.title);
    _descriptionController =
        TextEditingController(text: task.description ?? '');
    _status = task.status;
    _type = task.type;
    _discipline = task.discipline;
    _assigneeIds = {...task.assigneeIds};
    // Only preselect a project the picker knows about, so an unknown id
    // doesn't break the dropdown's value lookup.
    _projectId = widget.projects.any((p) => p.id == task.projectId)
        ? task.projectId
        : null;
    _startDate = task.startAt;
    _dueDate = task.dueAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();
    await runSubmit(() async {
      final updated = await widget.controller.updateTask(
        taskId: widget.task.id,
        title: _titleController.text.trim(),
        description: description.isEmpty ? null : description,
        clearDescription: description.isEmpty,
        status: _status,
        type: _type,
        discipline: _discipline,
        startAt: _startDate,
        clearStartAt: _startDate == null,
        dueAt: _dueDate,
        clearDueAt: _dueDate == null,
        assigneeIds: _assigneeIds.toList(growable: false),
        projectId: _projectId,
      );
      if (mounted) Navigator.pop(context, updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormDialog(
      title: 'Edit task',
      formKey: _formKey,
      width: 460,
      busy: submitting,
      error: submitError,
      submitLabel: 'Save changes',
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
        if (widget.projects.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _projectId,
            decoration: const InputDecoration(labelText: 'Project'),
            items: [
              for (final project in widget.projects)
                DropdownMenuItem<int?>(
                  value: project.id,
                  child: Text(project.name),
                ),
            ],
            onChanged: (value) => setState(() => _projectId = value),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Assigned to',
          style:
              theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (widget.users.isEmpty)
          MutedText('No teammates available.', style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final user in widget.users)
                FilterChip(
                  label: Text(user.displayName),
                  selected: _assigneeIds.contains(user.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _assigneeIds.add(user.id);
                    } else {
                      _assigneeIds.remove(user.id);
                    }
                  }),
                ),
            ],
          ),
        if (_assigneeIds.isEmpty) ...[
          const SizedBox(height: 6),
          MutedText(
            'Saving with nobody selected leaves this task unassigned.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 20),
        TaskDateFields(
          startDate: _startDate,
          dueDate: _dueDate,
          editingExisting: true,
          onChanged: (start, due) => setState(() {
            _startDate = start;
            _dueDate = due;
          }),
        ),
      ],
    );
  }
}
