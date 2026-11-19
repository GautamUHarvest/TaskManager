import 'package:material_ui/material_ui.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../tasks/task_models.dart';
import '../tasks/task_widgets.dart';
import 'profile_screen.dart';
import 'task_detail_screen.dart';

enum _WorkspaceSection {
  home,
  allTasks,
  assignedToMe,
  completedTasks,
  createTask,
  profile,
  allUsers,
}

class TaskWorkspaceScreen extends StatefulWidget {
  const TaskWorkspaceScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<TaskWorkspaceScreen> createState() => _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends State<TaskWorkspaceScreen> {
  _WorkspaceSection _section = _WorkspaceSection.home;

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

  Future<void> _loadUsers() async {
    try {
      final users = await widget.controller.allUsers();
      if (!mounted) return;
      setState(() {
        _usersById = {for (final user in users) user.id: user};
      });
    } catch (_) {
      // The assignee labels simply fall back to "User #id" if this fails.
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await widget.controller.allProjects();
      if (!mounted) return;
      setState(() => _projects = projects);
    } catch (_) {
      // If this fails the Create Task pane falls back to the local
      // "Unidentified" stand-in below so task creation isn't blocked.
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final items = await widget.controller.notifications();
      if (!mounted) return;
      setState(() {
        _unreadCount = items.where((item) => !item.isRead).length;
      });
    } catch (_) {
      // No badge if notifications can't be loaded.
    }
  }

  String _assigneeLabel(int? assigneeId) {
    if (assigneeId == null) return 'Unassigned';
    if (assigneeId == widget.controller.currentUser?.id) return 'You';
    final user = _usersById[assigneeId];
    return user?.displayName ?? 'User #$assigneeId';
  }

  /// Human-readable label for all of a task's assignees. Falls back to the
  /// single [Task.assigneeId] when the backend still returns only that.
  String _assigneesLabelFor(Task task) {
    final ids = task.assigneeIds.isNotEmpty
        ? task.assigneeIds
        : (task.assigneeId == null ? const <int>[] : [task.assigneeId!]);
    if (ids.isEmpty) return 'Unassigned';
    final names = ids.map(_assigneeLabel).toList();
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    return '${names[0]} +${names.length - 1} others';
  }

  /// Project name for display on a task card, or null if the task carries no
  /// project or its project isn't loaded yet.
  String? _projectNameFor(Task task) {
    if (task.projectId == null) return null;
    for (final project in _projects) {
      if (project.id == task.projectId) return project.name;
    }
    return null;
  }

  /// "Display Name · EMP123" for the task creator (shown as "Assigned by").
  String _createdByLabel(int? createdById) {
    if (createdById == null) return 'Unknown';
    final user = _usersById[createdById];
    if (user == null) return 'User #$createdById';
    return '${user.displayName} · ${user.employeeId}';
  }

  /// Open the full-screen detail page for [task]. Returns when it is popped so
  /// the calling list can refresh (status/subtasks may have changed).
  Future<void> _openTask(Task task) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailScreen(
          controller: widget.controller,
          taskId: task.id,
          usersById: _usersById,
          projectsById: {for (final project in _projects) project.id: project},
        ),
      ),
    );
  }

  void _openSection(_WorkspaceSection section) {
    setState(() => _section = section);
    Navigator.of(context).pop();
  }

  void _goToCreatedTasksView() {
    setState(() => _section = _WorkspaceSection.allTasks);
  }

  Future<void> _showNotifications() {
    return showDialog<void>(
      context: context,
      builder: (context) => _NotificationsDialog(controller: widget.controller),
    ).whenComplete(_loadUnreadCount);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 560;
    return Scaffold(
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
            _BrandMark(),
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
            icon: _unreadCount > 0
                ? Badge(
                    label: Text('$_unreadCount'),
                    child: const Icon(Icons.notifications_none_outlined),
                  )
                : const Icon(Icons.notifications_none_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Profile',
              isSelected: _section == _WorkspaceSection.profile,
              onPressed: () =>
                  setState(() => _section = _WorkspaceSection.profile),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: _buildContent(),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  _BrandMark(),
                  const SizedBox(width: 12),
                  Text(
                    'Task Manager',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: FilledButton.icon(
                onPressed: () => _openSection(_WorkspaceSection.createTask),
                icon: const Icon(Icons.add),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('New Task'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _navigationItem(
                    icon: Icons.space_dashboard_outlined,
                    label: 'Dashboard',
                    section: _WorkspaceSection.home,
                  ),
                  _navigationItem(
                    icon: Icons.assignment_ind_outlined,
                    label: 'My Tasks',
                    section: _WorkspaceSection.assignedToMe,
                  ),
                  _navigationItem(
                    icon: Icons.list_alt_outlined,
                    label: 'All Tasks',
                    section: _WorkspaceSection.allTasks,
                  ),
                  _navigationItem(
                    icon: Icons.check_circle_outline,
                    label: 'Completed',
                    section: _WorkspaceSection.completedTasks,
                  ),
                  _navigationItem(
                    icon: Icons.groups_outlined,
                    label: 'Team',
                    section: _WorkspaceSection.allUsers,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                selected: _section == _WorkspaceSection.profile,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.person_outline, size: 18),
                ),
                title: const Text('Profile'),
                subtitle: const Text('Account & sign out'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _openSection(_WorkspaceSection.profile),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigationItem({
    required IconData icon,
    required String label,
    required _WorkspaceSection section,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        selected: _section == section,
        leading: Icon(icon),
        title: Text(label),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onTap: () => _openSection(section),
      ),
    );
  }

  Widget _buildContent() {
    switch (_section) {
      case _WorkspaceSection.home:
        return _DashboardPane(
          controller: widget.controller,
          onOpenCreate: () =>
              setState(() => _section = _WorkspaceSection.createTask),
          onOpenMine: () =>
              setState(() => _section = _WorkspaceSection.assignedToMe),
          onOpenAll: () =>
              setState(() => _section = _WorkspaceSection.allTasks),
          onOpenCompleted: () =>
              setState(() => _section = _WorkspaceSection.completedTasks),
        );
      case _WorkspaceSection.assignedToMe:
        return _TaskListPane(
          key: const ValueKey('mine'),
          title: 'My Tasks',
          emptyMessage: 'You have no tasks assigned to you yet.',
          loader: widget.controller.myTasks,
          assigneesLabel: _assigneesLabelFor,
          projectName: _projectNameFor,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.allTasks:
        return _TaskListPane(
          key: const ValueKey('all'),
          title: 'All Tasks',
          emptyMessage: 'No tasks have been created yet.',
          loader: widget.controller.allTasks,
          assigneesLabel: _assigneesLabelFor,
          projectName: _projectNameFor,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.completedTasks:
        return _TaskListPane(
          key: const ValueKey('completed'),
          title: 'Completed',
          emptyMessage: 'No tasks have been completed yet.',
          loader: widget.controller.completedTasks,
          assigneesLabel: _assigneesLabelFor,
          projectName: _projectNameFor,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.createTask:
        return _CreateTaskPane(
          controller: widget.controller,
          users: _usersById.values.toList(growable: false),
          projects: _projects,
          onProjectCreated: (project) {
            setState(() => _projects = [..._projects, project]);
          },
          onCreated: _goToCreatedTasksView,
        );
      case _WorkspaceSection.profile:
        return ProfileContent(controller: widget.controller);
      case _WorkspaceSection.allUsers:
        return _TeamPane(controller: widget.controller);
    }
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        'T',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Shared scrollable page frame: a sticky-feeling header with a title and an
/// optional trailing action, above the page body, centered with a max width.
class _PaneScaffold extends StatelessWidget {
  const _PaneScaffold({
    required this.title,
    required this.child,
    this.trailing,
    this.maxWidth = 920,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: theme.textTheme.titleMedium),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskListPane extends StatefulWidget {
  const _TaskListPane({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.loader,
    required this.assigneesLabel,
    required this.projectName,
    required this.createdByLabel,
    required this.onOpenTask,
  });

  final String title;
  final String emptyMessage;
  final Future<List<Task>> Function() loader;
  final String Function(Task) assigneesLabel;
  final String? Function(Task) projectName;
  final String Function(int?) createdByLabel;
  final Future<void> Function(Task) onOpenTask;

  @override
  State<_TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends State<_TaskListPane> {
  late Future<List<Task>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() => setState(() => _future = widget.loader());

  @override
  Widget build(BuildContext context) {
    return _PaneScaffold(
      title: widget.title,
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<List<Task>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                _MessageCard(
                  message: _errorText(snapshot.error),
                  action: FilledButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            );
          }
          final tasks = snapshot.data ?? const [];
          if (tasks.isEmpty) {
            return ListView(
              children: [_MessageCard(message: widget.emptyMessage)],
            );
          }
          return ListView.separated(
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _TaskCard(
              task: tasks[index],
              assigneesLabel: widget.assigneesLabel(tasks[index]),
              projectName: widget.projectName(tasks[index]),
              createdByLabel: widget.createdByLabel,
              onTap: () async {
                await widget.onOpenTask(tasks[index]);
                // Refresh on return — status/subtasks may have changed.
                if (mounted) _reload();
              },
            ),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.assigneesLabel,
    required this.projectName,
    required this.createdByLabel,
    required this.onTap,
  });

  final Task task;
  final String assigneesLabel;
  final String? projectName;
  final String Function(int?) createdByLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TaskStatusChip(status: task.status),
                ],
              ),
              if (task.description != null && task.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  task.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Project tag + (optionally) type/discipline tags. Project is
              // always shown when known so the task's "home" is visible at a
              // glance.
              if (projectName != null ||
                  task.type != TaskType.decide ||
                  task.discipline != TaskDiscipline.decide)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (projectName != null)
                        TagChip(label: 'Project: $projectName'),
                      if (task.type != TaskType.decide)
                        TagChip(label: task.type.label),
                      if (task.discipline != TaskDiscipline.decide)
                        TagChip(label: task.discipline.label),
                    ],
                  ),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _MetaChip(
                    icon: Icons.person_outline,
                    label: assigneesLabel,
                  ),
                  _MetaChip(
                    icon: Icons.badge_outlined,
                    label: 'By ${createdByLabel(task.createdById)}',
                  ),
                  if (task.startAt != null)
                    _MetaChip(
                      icon: Icons.play_circle_outline,
                      label: 'Starts ${formatTaskDate(task.startAt!)}',
                    ),
                  if (task.dueAt != null)
                    _MetaChip(
                      icon: Icons.event_outlined,
                      label: 'Due ${formatTaskDate(task.dueAt!)}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

class _DashboardPane extends StatefulWidget {
  const _DashboardPane({
    required this.controller,
    required this.onOpenCreate,
    required this.onOpenMine,
    required this.onOpenAll,
    required this.onOpenCompleted,
  });

  final AuthController controller;
  final VoidCallback onOpenCreate;
  final VoidCallback onOpenMine;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenCompleted;

  @override
  State<_DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<_DashboardPane> {
  late Future<List<Task>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.allTasks();
  }

  void _reload() => setState(() => _future = widget.controller.allTasks());

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.currentUser?.displayName;
    return _PaneScaffold(
      title: name == null ? 'Dashboard' : 'Welcome, ${name.split(' ').first}',
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<List<Task>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                _MessageCard(
                  message: _errorText(snapshot.error),
                  action: FilledButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            );
          }
          final tasks = snapshot.data ?? const [];
          final myId = widget.controller.currentUser?.id;
          final counts = <TaskStatus, int>{};
          for (final task in tasks) {
            counts[task.status] = (counts[task.status] ?? 0) + 1;
          }
          final mine =
              tasks.where((task) => task.assigneeId == myId).length;
          return ListView(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatTile(
                    label: 'All tasks',
                    value: '${tasks.length}',
                    onTap: widget.onOpenAll,
                  ),
                  _StatTile(
                    label: 'Assigned to me',
                    value: '$mine',
                    onTap: widget.onOpenMine,
                  ),
                  _StatTile(
                    label: 'In progress',
                    value: '${counts[TaskStatus.inProgress] ?? 0}',
                    onTap: widget.onOpenAll,
                  ),
                  _StatTile(
                    label: 'Blocked',
                    value: '${counts[TaskStatus.blocked] ?? 0}',
                    onTap: widget.onOpenAll,
                  ),
                  _StatTile(
                    label: 'Done',
                    value: '${counts[TaskStatus.done] ?? 0}',
                    onTap: widget.onOpenCompleted,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick actions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: widget.onOpenCreate,
                            icon: const Icon(Icons.add),
                            label: const Text('New Task'),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.onOpenMine,
                            icon: const Icon(Icons.assignment_ind_outlined),
                            label: const Text('My Tasks'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamPane extends StatefulWidget {
  const _TeamPane({required this.controller});

  final AuthController controller;

  @override
  State<_TeamPane> createState() => _TeamPaneState();
}

class _TeamPaneState extends State<_TeamPane> {
  late Future<List<AuthUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.allUsers();
  }

  void _reload() => setState(() => _future = widget.controller.allUsers());

  @override
  Widget build(BuildContext context) {
    return _PaneScaffold(
      title: 'Team',
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<List<AuthUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                _MessageCard(
                  message: _errorText(snapshot.error),
                  action: FilledButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            );
          }
          final users = snapshot.data ?? const [];
          if (users.isEmpty) {
            return ListView(
              children: const [
                _MessageCard(message: 'No team members found.'),
              ],
            );
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    user.displayName.isEmpty
                        ? '?'
                        : user.displayName[0].toUpperCase(),
                  ),
                ),
                title: Text(user.displayName),
                subtitle: Text('${user.employeeId} · ${user.email}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _CreateTaskPane extends StatefulWidget {
  const _CreateTaskPane({
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
  State<_CreateTaskPane> createState() => _CreateTaskPaneState();
}

class _CreateTaskPaneState extends State<_CreateTaskPane> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  TaskStatus _status = TaskStatus.todo;
  TaskType _type = TaskType.decide;
  TaskDiscipline _discipline = TaskDiscipline.decide;
  /// Users this task will be assigned to. A task can have more than one
  /// assignee; ordering is the order the user ticked them.
  final List<int> _assigneeIds = [];
  int? _projectId;
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the backend's built-in "Unidentified" project when it is
    // present in the list; falls back to the first project otherwise, and to
    // null when no projects have loaded yet (we send no project_id then).
    _projectId = _defaultProjectId();
  }

  int? _defaultProjectId() {
    if (widget.projects.isEmpty) return null;
    final defaultProject = widget.projects.firstWhere(
      (project) => project.isDefault,
      orElse: () => widget.projects.first,
    );
    return defaultProject.id;
  }

  @override
  void didUpdateWidget(_CreateTaskPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the workspace loads projects (or a new one is created) and our
    // dropdown has no value yet, adopt the default so the form validates.
    if (_projectId == null ||
        !widget.projects.any((project) => project.id == _projectId)) {
      setState(() => _projectId = _defaultProjectId());
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _chooseStartDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _chooseDueDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate ?? today,
      // Due must not precede start.
      firstDate: _startDate ?? DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _createProject() async {
    final created = await showDialog<Project>(
      context: context,
      builder: (_) => _NewProjectDialog(controller: widget.controller),
    );
    if (created == null || !mounted) return;
    widget.onProjectCreated(created);
    setState(() => _projectId = created.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Project "${created.name}" created.')),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created.')),
      );
      widget.onCreated();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the server. Check the connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaneScaffold(
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
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Enter a title';
                        if (text.length > 200) {
                          return 'Title must be 200 characters or fewer';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<TaskStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final status in TaskStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _status = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<TaskType>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        for (final type in TaskType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<TaskDiscipline>(
                      initialValue: _discipline,
                      decoration:
                          const InputDecoration(labelText: 'Discipline'),
                      items: [
                        for (final discipline in TaskDiscipline.values)
                          DropdownMenuItem(
                            value: discipline,
                            child: Text(discipline.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _discipline = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    _ProjectPickerField(
                      projects: widget.projects,
                      selectedProjectId: _projectId,
                      onChanged: (value) =>
                          setState(() => _projectId = value),
                      onCreateProject: _createProject,
                    ),
                    const SizedBox(height: 16),
                    _AssigneePickerField(
                      users: widget.users,
                      selectedIds: _assigneeIds,
                      onChanged: (ids) => setState(() {
                        _assigneeIds
                          ..clear()
                          ..addAll(ids);
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseStartDate,
                            icon: const Icon(Icons.play_circle_outline),
                            label: Text(
                              _startDate == null
                                  ? 'Start date (optional)'
                                  : 'Starts ${formatTaskDate(_startDate!)}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseDueDate,
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              _dueDate == null
                                  ? 'Due date (optional)'
                                  : 'Due ${formatTaskDate(_dueDate!)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_startDate != null || _dueDate != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _startDate = null;
                            _dueDate = null;
                          }),
                          child: const Text('Clear dates'),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
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

class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog({required this.controller});

  final AuthController controller;

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    // Once the dialog has fetched the notifications, flag the ids as seen so
    // they drop off subsequent reads / badge counts.
    _future = widget.controller.notifications().then((items) {
      widget.controller
          .markNotificationsRead(items.map((item) => item.id));
      return items;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notifications'),
      content: SizedBox(
        width: 400,
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(_errorText(snapshot.error));
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const Text('You have no notifications.');
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.isRead
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(item.message),
                    subtitle: item.createdAt == null
                        ? null
                        : Text(formatTaskDate(item.createdAt!)),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _errorText(Object? error) =>
    error is AuthApiException ? error.message : 'Something went wrong.';

/// A dropdown-shaped field that picks one project and offers a trailing
/// "+ New" button to create one inline. When no projects have loaded yet it
/// shows a disabled placeholder with the built-in "Unidentified" label so
/// the user sees what the default would be.
class _ProjectPickerField extends StatelessWidget {
  const _ProjectPickerField({
    required this.projects,
    required this.selectedProjectId,
    required this.onChanged,
    required this.onCreateProject,
  });

  final List<Project> projects;
  final int? selectedProjectId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context) {
    // The "Unidentified" project sorts first on the server; keep that order.
    final items = [
      for (final project in projects)
        DropdownMenuItem<int>(
          value: project.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(project.name)),
              if (project.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'default',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: selectedProjectId,
            decoration: InputDecoration(
              labelText: 'Project',
              helperText: projects.isEmpty
                  ? 'No projects loaded yet. Default will be "Unidentified".'
                  : null,
            ),
            items: items,
            onChanged: projects.isEmpty ? null : onChanged,
            validator: (value) {
              // The server defaults to "Unidentified" when no project_id is
              // sent, so an empty selection is only an error when projects
              // did load but none was picked.
              if (projects.isNotEmpty && value == null) {
                return 'Pick a project';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: onCreateProject,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New'),
          ),
        ),
      ],
    );
  }
}

/// Multi-select assignee field. Shows a chip for each picked user and a menu
/// of remaining users behind an "Add teammate" button. An empty picker means
/// the task is unassigned (the server still accepts it).
class _AssigneePickerField extends StatelessWidget {
  const _AssigneePickerField({
    required this.users,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<AuthUser> users;
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  /// Human-friendly label for a user. Falls back through display name →
  /// employee id → email → "User #id" so there is always something to show
  /// even when the server left a field blank.
  static String _nameFor(AuthUser user) {
    final name = user.displayName.trim();
    if (name.isNotEmpty) return name;
    if (user.employeeId.isNotEmpty) return user.employeeId;
    if (user.email.isNotEmpty) return user.email;
    return 'User #${user.id}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userById = {for (final user in users) user.id: user};
    final remaining =
        users.where((user) => !selectedIds.contains(user.id)).toList();

    void removeAt(int userId) {
      final next = [...selectedIds]..remove(userId);
      onChanged(next);
    }

    void addId(int userId) {
      if (selectedIds.contains(userId)) return;
      onChanged([...selectedIds, userId]);
    }

    // When the roster hasn't arrived yet (initial load, network blip) say so
    // instead of pretending nobody is addable.
    final rosterEmpty = users.isEmpty;
    final addLabel = rosterEmpty
        ? 'Loading teammates…'
        : remaining.isEmpty
            ? 'Everyone added'
            : 'Add teammate';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Assign to (one or more)',
            helperText: selectedIds.isEmpty
                ? 'Leave empty for "Unassigned".'
                : '${selectedIds.length} assigned',
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (selectedIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'No one yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final id in selectedIds)
                InputChip(
                  label: Text(
                    userById[id] == null
                        ? 'User #$id'
                        : _nameFor(userById[id]!),
                  ),
                  onDeleted: () => removeAt(id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // PopupMenuButton with its own child — no inner button, since an
        // inner button would swallow the tap before PopupMenuButton saw it
        // and the menu would never open.
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<int>(
            enabled: remaining.isNotEmpty,
            onSelected: addId,
            tooltip: addLabel,
            itemBuilder: (context) => [
              for (final user in remaining)
                PopupMenuItem<int>(
                  value: user.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor:
                            theme.colorScheme.onPrimaryContainer,
                        child: Text(
                          _nameFor(user)[0].toUpperCase(),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          user.employeeId.isEmpty
                              ? _nameFor(user)
                              : '${_nameFor(user)} · ${user.employeeId}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: remaining.isEmpty
                      ? theme.colorScheme.outlineVariant
                      : theme.colorScheme.outline,
                ),
                color: remaining.isEmpty
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_alt_1,
                    size: 18,
                    color: remaining.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    addLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: remaining.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog to create a new project from the task-create pane. Returns the
/// created [Project] on submit, null on cancel.
class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.controller});

  final AuthController controller;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final project = await widget.controller.createProject(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      if (mounted) Navigator.pop(context, project);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the server. Check the connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                maxLength: 120,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter a project name';
                  if (text.length > 120) {
                    return 'Name must be 120 characters or fewer';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
