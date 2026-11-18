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
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
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
          assigneeLabel: _assigneeLabel,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.allTasks:
        return _TaskListPane(
          key: const ValueKey('all'),
          title: 'All Tasks',
          emptyMessage: 'No tasks have been created yet.',
          loader: widget.controller.allTasks,
          assigneeLabel: _assigneeLabel,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.completedTasks:
        return _TaskListPane(
          key: const ValueKey('completed'),
          title: 'Completed',
          emptyMessage: 'No tasks have been completed yet.',
          loader: widget.controller.completedTasks,
          assigneeLabel: _assigneeLabel,
          createdByLabel: _createdByLabel,
          onOpenTask: _openTask,
        );
      case _WorkspaceSection.createTask:
        return _CreateTaskPane(
          controller: widget.controller,
          users: _usersById.values.toList(growable: false),
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
    required this.assigneeLabel,
    required this.createdByLabel,
    required this.onOpenTask,
  });

  final String title;
  final String emptyMessage;
  final Future<List<Task>> Function() loader;
  final String Function(int?) assigneeLabel;
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
              assigneeLabel: widget.assigneeLabel,
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
    required this.assigneeLabel,
    required this.createdByLabel,
    required this.onTap,
  });

  final Task task;
  final String Function(int?) assigneeLabel;
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
              // Type + discipline sit together as subtle tags; hidden while
              // they're still "to be decided" to avoid noise.
              if (task.type != TaskType.decide ||
                  task.discipline != TaskDiscipline.decide)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
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
                    label: assigneeLabel(task.assigneeId),
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
    required this.onCreated,
  });

  final AuthController controller;
  final List<AuthUser> users;
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
  int? _assigneeId;
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;

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
        assigneeId: _assigneeId,
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
                    DropdownButtonFormField<int?>(
                      initialValue: _assigneeId,
                      decoration:
                          const InputDecoration(labelText: 'Assign to'),
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
                      onChanged: (value) =>
                          setState(() => _assigneeId = value),
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
    _future = widget.controller.notifications();
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
