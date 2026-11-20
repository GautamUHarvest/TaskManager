import 'package:material_ui/material_ui.dart';

import '../../auth/auth_api.dart';
import '../../auth/auth_controller.dart';
import '../../common/snackbar.dart';
import '../../common/submit_state.dart';
import '../../common/widgets/button_spinner.dart';
import '../../common/widgets/form_error_text.dart';
import '../../common/widgets/pane_scaffold.dart';
import '../../tasks/task_models.dart';
import '../../tasks/widgets/assignee_picker_field.dart';
import '../../tasks/widgets/new_project_dialog.dart';
import '../../tasks/widgets/project_picker_field.dart';
import '../../tasks/widgets/task_date_fields.dart';
import '../../tasks/widgets/task_form_fields.dart';

/// Full-page form that creates a top-level task.
class CreateTaskPane extends StatefulWidget {
  const CreateTaskPane({
    super.key,
    required this.controller,
    required this.users,
    required this.projects,
    required this.onProjectCreated,
    required this.onCreated,
  });

  final AuthController controller;
  final List<AuthUser> users;
  final List<Project> projects;
  final ValueChanged<Project> onProjectCreated;
  final VoidCallback onCreated;

  @override
  State<CreateTaskPane> createState() => _CreateTaskPaneState();
}

class _CreateTaskPaneState extends State<CreateTaskPane>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  TaskStatus _status = TaskStatus.todo;
  TaskType _type = TaskType.decide;
  TaskDiscipline _discipline = TaskDiscipline.decide;

  /// Users this task will be assigned to, in the order they were picked.
  List<int> _assigneeIds = const [];
  int? _projectId;
  DateTime? _startDate;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _projectId = _defaultProjectId();
  }

  /// The backend's built-in "Unidentified" project when it is loaded, else
  /// the first project, else null (no project_id is sent then and the
  /// server applies its default).
  int? _defaultProjectId() {
    if (widget.projects.isEmpty) return null;
    return widget.projects
        .firstWhere(
          (project) => project.isDefault,
          orElse: () => widget.projects.first,
        )
        .id;
  }

  @override
  void didUpdateWidget(CreateTaskPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the workspace loads projects (or a new one is created) and our
    // dropdown has no valid value yet, adopt the default so the form
    // validates.
    if (_projectId == null ||
        !widget.projects.any((project) => project.id == _projectId)) {
      _projectId = _defaultProjectId();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createProject() async {
    final created = await showDialog<Project>(
      context: context,
      builder: (_) => NewProjectDialog(controller: widget.controller),
    );
    if (created == null || !mounted) return;
    widget.onProjectCreated(created);
    setState(() => _projectId = created.id);
    context.showSnackMessage('Project "${created.name}" created.');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await runSubmit(() async {
      await widget.controller.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
        type: _type,
        discipline: _discipline,
        startAt: _startDate,
        dueAt: _dueDate,
        assigneeIds: List.unmodifiable(_assigneeIds),
        projectId: _projectId,
      );
      if (!mounted) return;
      context.showSnackMessage('Task created.');
      widget.onCreated();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PaneScaffold(
      title: 'Create Task',
      maxWidth: 720,
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TaskTitleField(controller: _titleController),
                    const SizedBox(height: 16),
                    TaskDescriptionField(
                      controller: _descriptionController,
                      minLines: 3,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 8),
                    TaskClassificationFields(
                      status: _status,
                      type: _type,
                      discipline: _discipline,
                      onStatusChanged: (value) =>
                          setState(() => _status = value),
                      onTypeChanged: (value) => setState(() => _type = value),
                      onDisciplineChanged: (value) =>
                          setState(() => _discipline = value),
                    ),
                    const SizedBox(height: 16),
                    ProjectPickerField(
                      projects: widget.projects,
                      selectedProjectId: _projectId,
                      onChanged: (value) =>
                          setState(() => _projectId = value),
                      onCreateProject: _createProject,
                    ),
                    const SizedBox(height: 16),
                    AssigneePickerField(
                      users: widget.users,
                      selectedIds: _assigneeIds,
                      onChanged: (ids) => setState(() => _assigneeIds = ids),
                    ),
                    const SizedBox(height: 16),
                    TaskDateFields(
                      startDate: _startDate,
                      dueDate: _dueDate,
                      horizontal: true,
                      onChanged: (start, due) => setState(() {
                        _startDate = start;
                        _dueDate = due;
                      }),
                    ),
                    if (submitError != null) ...[
                      const SizedBox(height: 16),
                      FormErrorText(submitError!),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: submitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: submitting
                            ? const ButtonSpinner(size: 20)
                            : const Text('Create Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
