import 'package:material_ui/material_ui.dart';

import '../../common/error_messages.dart';
import '../../common/widgets/message_card.dart';
import '../../common/widgets/pane_scaffold.dart';
import '../../common/widgets/refresh_bar.dart';
import '../../tasks/task_models.dart';
import '../../tasks/user_directory.dart';
import 'task_card.dart';

/// Opens a task's detail screen. Resolves to the task's id when it was
/// deleted there, else null. [onTaskChanged] fires for in-place status/edit
/// updates while that screen is open.
typedef OpenTaskCallback = Future<int?> Function(
  Task task, {
  ValueChanged<Task>? onTaskChanged,
});

/// A refreshable list of tasks (My Tasks / All Tasks / Completed).
///
/// Changes made on a task's detail screen are applied to the rows here
/// immediately (patched / removed locally) and then reconciled by a refetch,
/// which keeps the current rows on screen rather than blanking to a spinner.
class TaskListPane extends StatefulWidget {
  const TaskListPane({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.loader,
    required this.directory,
    required this.projectsById,
    required this.onOpenTask,
  });

  final String title;
  final String emptyMessage;
  final Future<List<Task>> Function() loader;
  final UserDirectory directory;
  final Map<int, Project> projectsById;
  final OpenTaskCallback onOpenTask;

  @override
  State<TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends State<TaskListPane> {
  late Future<List<Task>> _future;

  /// Tasks deleted from the detail screen. They are filtered out of the
  /// rendered list immediately, so a deleted row can never reappear while the
  /// refetch is in flight or if a cached response still carries it. Never
  /// cleared: a deleted task is gone server-side for good, so the set stays
  /// small and filtering it forever is harmless.
  final Set<int> _deletedIds = <int>{};

  /// Tasks updated from the detail screen, keyed by id. Applied over whatever
  /// the last fetch returned so a status change or edit shows on the row
  /// right away. A patch stops being applied once the fetched copy reaches
  /// the same `version`, so a later edit by someone else is never shadowed by
  /// our stale local copy.
  final Map<int, Task> _patched = <int, Task>{};

  /// Last successfully loaded list, kept so a refresh can leave the current
  /// rows on screen instead of blanking to a spinner.
  List<Task>? _lastTasks;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() => setState(() => _future = widget.loader());

  /// [loaded] with local deletes and newer local patches applied.
  List<Task> _visibleTasks(List<Task> loaded) {
    return loaded
        .where((task) => !_deletedIds.contains(task.id))
        .map((task) {
          // Prefer a locally-patched copy only while the fetched one is
          // genuinely older — the request behind it may have been in flight
          // when the edit landed, or served from cache.
          final patch = _patched[task.id];
          if (patch == null || task.version >= patch.version) return task;
          return patch;
        })
        .toList(growable: false);
  }

  Future<void> _open(Task task) async {
    final deletedId = await widget.onOpenTask(
      task,
      // Fires while the detail screen is open, so the row behind it is
      // already up to date when the user returns.
      onTaskChanged: (updated) {
        if (mounted) setState(() => _patched[updated.id] = updated);
      },
    );
    if (!mounted) return;
    // Deleted down there: hide the row now, before the refetch.
    if (deletedId != null) setState(() => _deletedIds.add(deletedId));
    // Refresh on return — status/subtasks may have changed.
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PaneScaffold(
      title: widget.title,
      trailing: RefreshIconButton(onPressed: _reload),
      child: FutureBuilder<List<Task>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasData) _lastTasks = snapshot.data;
          final loaded = _lastTasks;
          final refreshing =
              snapshot.connectionState == ConnectionState.waiting;

          // Nothing to show yet: first load, or an error before any data
          // arrived. Once a list has loaded we keep showing it through a
          // refresh, so returning from a task's detail page lands straight
          // back on the list with the change already applied.
          if (loaded == null) {
            if (refreshing) {
              return const Center(child: CircularProgressIndicator());
            }
            return MessageListView(
              message: errorMessage(snapshot.error),
              onRetry: _reload,
            );
          }

          final tasks = _visibleTasks(loaded);
          return RefreshingColumn(
            refreshing: refreshing,
            child: tasks.isEmpty
                ? MessageListView(message: widget.emptyMessage)
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return TaskCard(
                        task: task,
                        assigneesLabel:
                            widget.directory.assigneesSummary(task),
                        createdByLabel: widget.directory
                            .fullLabel(task.createdById, ifNull: 'Unknown'),
                        projectName: widget.projectsById[task.projectId]?.name,
                        onTap: () => _open(task),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
