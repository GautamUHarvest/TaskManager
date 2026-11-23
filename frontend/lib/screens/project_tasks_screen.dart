import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../common/error_messages.dart';
import '../common/file_download.dart';
import '../common/snackbar.dart';
import '../common/widgets/button_spinner.dart';
import '../common/widgets/muted_text.dart';
import '../tasks/project_csv.dart';
import '../tasks/task_models.dart';
import '../tasks/user_directory.dart';
import 'workspace/task_list_pane.dart';

/// Full-screen list of one project's tasks (subtasks included), with an
/// "Export CSV" action. Tapping a task opens its detail screen via
/// [onOpenTask], exactly as the workspace task lists do.
class ProjectTasksScreen extends StatefulWidget {
  const ProjectTasksScreen({
    super.key,
    required this.controller,
    required this.project,
    required this.directory,
    required this.projectsById,
    required this.onOpenTask,
  });

  final AuthController controller;
  final Project project;
  final UserDirectory directory;
  final Map<int, Project> projectsById;
  final OpenTaskCallback onOpenTask;

  @override
  State<ProjectTasksScreen> createState() => _ProjectTasksScreenState();
}

class _ProjectTasksScreenState extends State<ProjectTasksScreen> {
  bool _exporting = false;

  Future<List<Task>> _load() =>
      widget.controller.projectTasks(widget.project.id);

  /// Fetches the project's tasks fresh (so the file matches the server, not
  /// whatever the list last showed) and hands the CSV to the browser.
  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final tasks = await _load();
      final filename = projectCsvFilename(widget.project);
      downloadTextFile(
        filename,
        buildProjectCsv(
          project: widget.project,
          tasks: tasks,
          directory: widget.directory,
        ),
      );
      if (!mounted) return;
      final count = tasks.length == 1 ? '1 task' : '${tasks.length} tasks';
      context.showSnackMessage('Exported $count to $filename');
    } catch (error) {
      if (!mounted) return;
      context.showSnackMessage(
        errorMessage(error, fallback: 'Could not export the project.'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.project.description?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Project')),
      body: TaskListPane(
        title: widget.project.name,
        emptyMessage: 'This project has no tasks yet.',
        loader: _load,
        directory: widget.directory,
        projectsById: widget.projectsById,
        onOpenTask: widget.onOpenTask,
        header: description.isEmpty
            ? const MutedText('No description')
            : Text(description),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : _exportCsv,
              icon: _exporting
                  ? const ButtonSpinner()
                  : const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ),
        ],
      ),
    );
  }
}
