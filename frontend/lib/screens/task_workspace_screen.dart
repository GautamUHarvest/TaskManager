import 'package:material_ui/material_ui.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../tasks/task_models.dart';
import '../tasks/user_directory.dart';
import 'profile_screen.dart';
import 'task_detail_screen.dart';
import 'workspace/blocker_alert_listener.dart';
import 'workspace/brand_mark.dart';
import 'workspace/create_task_pane.dart';
import 'workspace/dashboard_pane.dart';
import 'workspace/notifications_dialog.dart';
import 'workspace/task_list_pane.dart';
import 'workspace/team_pane.dart';
import 'workspace/workspace_drawer.dart';
import 'workspace/workspace_section.dart';

/// The signed-in shell: app bar (notifications bell + profile), navigation
/// drawer, and whichever [WorkspaceSection] pane is selected.
///
/// Loads the shared lookups once — the user directory (for names), projects,
/// and the unread count (for the bell badge) — and hands them to the panes.
/// Each pane fetches its own data.
class TaskWorkspaceScreen extends StatefulWidget {
  const TaskWorkspaceScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<TaskWorkspaceScreen> createState() => _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends State<TaskWorkspaceScreen> {
  WorkspaceSection _section = WorkspaceSection.home;

  Map<int, AuthUser> _usersById = const {};
  List<Project> _projects = const [];
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadProjects();
    _loadUnreadCount();
  }

  UserDirectory get _directory => UserDirectory(
        _usersById,
        currentUserId: widget.controller.currentUser?.id,
      );

  Map<int, Project> get _projectsById =>
      {for (final project in _projects) project.id: project};

  Future<void> _loadUsers() async {
    try {
      final users = await widget.controller.allUsers();
      if (!mounted) return;
      setState(() => _usersById = {for (final user in users) user.id: user});
    } catch (_) {
      // Names simply fall back to "User #id" if this fails.
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await widget.controller.allProjects();
      if (!mounted) return;
      setState(() => _projects = projects);
    } catch (_) {
      // The Create Task pane then sends no project and the server applies
      // its "Unidentified" default, so task creation isn't blocked.
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final items = await widget.controller.notifications();
      if (!mounted) return;
      setState(() => _unreadCount = items.where((item) => !item.isRead).length);
    } catch (_) {
      // No badge if notifications can't be loaded.
    }
  }

  void _show(WorkspaceSection section) => setState(() => _section = section);

  /// Opens the full-screen detail page for [task]. See [OpenTaskCallback].
  Future<int?> _openTask(Task task, {ValueChanged<Task>? onTaskChanged}) {
    return Navigator.of(context).push<int?>(
      MaterialPageRoute<int?>(
        builder: (_) => TaskDetailScreen(
          controller: widget.controller,
          taskId: task.id,
          directory: _directory,
          projectsById: _projectsById,
          onTaskChanged: onTaskChanged,
        ),
      ),
    );
  }

  Future<void> _showNotifications() {
    return showDialog<void>(
      context: context,
      builder: (context) => NotificationsDialog(controller: widget.controller),
    ).whenComplete(_loadUnreadCount);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 560;
    return BlockerAlertListener(
      controller: widget.controller,
      raisedByLabel: (id) => _directory.fullLabel(id, ifNull: 'Unknown'),
      // A blocker sets the task to 'blocked', so the bell count moved too.
      onAlertHandled: _loadUnreadCount,
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Open navigation',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              if (isWide) ...[
                const SizedBox(width: 10),
                const Text('Task Manager'),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: _showNotifications,
              icon: Badge(
                isLabelVisible: _unreadCount > 0,
                label: Text('$_unreadCount'),
                child: const Icon(Icons.notifications_none_outlined),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Profile',
                isSelected: _section == WorkspaceSection.profile,
                onPressed: () => _show(WorkspaceSection.profile),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ),
          ],
        ),
        drawer: WorkspaceDrawer(
          selected: _section,
          onSelect: (section) {
            _show(section);
            Navigator.of(context).pop(); // close the drawer
          },
        ),
        body: _buildPane(),
      ),
    );
  }

  Widget _buildPane() {
    switch (_section) {
      case WorkspaceSection.home:
        return DashboardPane(
          controller: widget.controller,
          onOpenCreate: () => _show(WorkspaceSection.createTask),
          onOpenMine: () => _show(WorkspaceSection.assignedToMe),
          onOpenAll: () => _show(WorkspaceSection.allTasks),
          onOpenCompleted: () => _show(WorkspaceSection.completedTasks),
        );
      case WorkspaceSection.assignedToMe:
        return _taskList(
          key: 'mine',
          title: 'My Tasks',
          emptyMessage: 'You have no tasks assigned to you yet.',
          loader: widget.controller.myTasks,
        );
      case WorkspaceSection.allTasks:
        return _taskList(
          key: 'all',
          title: 'All Tasks',
          emptyMessage: 'No tasks have been created yet.',
          loader: widget.controller.allTasks,
        );
      case WorkspaceSection.completedTasks:
        return _taskList(
          key: 'completed',
          title: 'Completed',
          emptyMessage: 'No tasks have been completed yet.',
          loader: widget.controller.completedTasks,
        );
      case WorkspaceSection.createTask:
        return CreateTaskPane(
          controller: widget.controller,
          users: _usersById.values.toList(growable: false),
          projects: _projects,
          onProjectCreated: (project) =>
              setState(() => _projects = [..._projects, project]),
          onCreated: () => _show(WorkspaceSection.allTasks),
        );
      case WorkspaceSection.profile:
        return ProfileContent(controller: widget.controller);
      case WorkspaceSection.allUsers:
        return TeamPane(controller: widget.controller);
    }
  }

  /// A task list pane. The [key] makes switching between lists recreate the
  /// pane, so each switch refetches.
  Widget _taskList({
    required String key,
    required String title,
    required String emptyMessage,
    required Future<List<Task>> Function() loader,
  }) {
    return TaskListPane(
      key: ValueKey(key),
      title: title,
      emptyMessage: emptyMessage,
      loader: loader,
      directory: _directory,
      projectsById: _projectsById,
      onOpenTask: _openTask,
    );
  }
}
