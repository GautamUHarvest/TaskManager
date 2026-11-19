import 'package:material_ui/material_ui.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../tasks/task_models.dart';
import '../tasks/task_widgets.dart';

/// Full-screen view of a single task: header + status control, its direct
/// subtasks, its notes, and a placeholder for the future comments feature.
///
/// Opened via `Navigator.push` (the app has no router by design). Subtasks and
/// notes can only be created by the task's assignee; status can be changed by
/// the assignee or the task's creator. These are convenience gates — the
/// backend re-enforces them.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.controller,
    required this.taskId,
    required this.usersById,
    this.projectsById = const {},
    this.onTaskChanged,
  });

  final AuthController controller;
  final int taskId;
  final Map<int, AuthUser> usersById;
  final Map<int, Project> projectsById;

  /// Fired with the server's updated task whenever its status is changed or
  /// it is edited here. Lets the opener (a task list, or a parent task's
  /// subtask list) refresh that row at the same moment rather than waiting
  /// for its own refetch after this screen is popped.
  final ValueChanged<Task>? onTaskChanged;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Future<TaskDetail> _future;

  /// Kept so a reload can keep showing the current task instead of blanking to
  /// a spinner — the new note/subtask/status then visibly appears in place.
  TaskDetail? _lastLoaded;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.taskDetail(widget.taskId);
  }

  void _reload() =>
      setState(() => _future = widget.controller.taskDetail(widget.taskId));

  /// Append [note] to the cached detail so the UI shows it immediately,
  /// without waiting for the follow-up `/task/detail` round-trip. The real
  /// fetch then reconciles (the server's note object will replace this one,
  /// matched by id).
  void _insertNote(TaskNote note) {
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task,
        subtasks: current.subtasks,
        // Notes come back oldest-first, so append.
        notes: [...current.notes, note],
        comments: current.comments,
      );
    });
  }

  /// Same idea as [_insertNote] for a freshly posted comment or reply: the
  /// composer's "post" await completes before the next /task/detail round-
  /// trip finishes, and users expect their message to appear instantly. The
  /// subsequent reload reconciles against the server's canonical copy.
  void _insertComment(TaskComment comment) {
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task,
        subtasks: current.subtasks,
        notes: current.notes,
        // Comments are returned flat oldest-first; the nested _CommentsSection
        // builds the tree from parent_comment_id, so a simple append slots a
        // reply into the right thread automatically.
        comments: [...current.comments, comment],
      );
    });
  }

  int? get _myId => widget.controller.currentUser?.id;

  /// "Display Name · EMP123", or a sensible fallback.
  String _userLabel(int? id) {
    if (id == null) return 'Unassigned';
    final user = widget.usersById[id];
    if (user == null) return 'User #$id';
    return '${user.displayName} · ${user.employeeId}';
  }

  Future<void> _changeStatus(Task task) async {
    final picked = await showDialog<TaskStatus>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change status'),
        children: [
          for (final status in TaskStatus.values)
            ListTile(
              leading: Icon(
                status == task.status
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: status == task.status
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(status.label),
              onTap: () => Navigator.pop(context, status),
            ),
        ],
      ),
    );
    if (picked == null || picked == task.status) return;
    try {
      final updated = await widget.controller.changeTaskStatus(
        taskId: task.id,
        status: picked,
      );
      if (!mounted) return;
      // Show the new status straight away, then reconcile.
      _applyTask(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status set to ${picked.label}.')),
      );
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _addSubtask(Task parent) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AddSubtaskDialog(
        controller: widget.controller,
        parent: parent,
        users: widget.usersById.values.toList(growable: false),
      ),
    );
    if (created == true) _reload();
  }

  /// Flags the task as blocked on another member and alerts them. They get a
  /// modal popup immediately if they have a tab open, and on their next
  /// connect otherwise.
  Future<void> _raiseBlocker(Task task) async {
    final myId = _myId;
    final candidates = widget.usersById.values
        // Flagging yourself is meaningless, and the server rejects it.
        .where((user) => user.id != myId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other members to flag.')),
      );
      return;
    }
    final updated = await showDialog<Task>(
      context: context,
      builder: (context) => _RaiseBlockerDialog(
        controller: widget.controller,
        task: task,
        candidates: candidates,
      ),
    );
    if (updated != null && mounted) {
      _applyTask(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blocker raised. They have been notified.')),
      );
      _reload();
    }
  }

  Future<void> _editTask(Task task) async {
    // The dialog hands back the server's updated task so the page can repaint
    // with the new values before the refetch lands.
    final updated = await showDialog<Task>(
      context: context,
      builder: (context) => _EditTaskDialog(
        controller: widget.controller,
        task: task,
        users: widget.usersById.values.toList(growable: false),
        projects: widget.projectsById.values.toList(growable: false),
      ),
    );
    if (updated != null && mounted) {
      _applyTask(updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Task updated.')));
      _reload();
    }
  }

  /// Deletes the task and leaves the screen — there is nothing left to show.
  /// The server refuses while subtasks remain, and that message is surfaced
  /// verbatim so the user knows what is in the way.
  Future<void> _deleteTask(Task task) async {
    final confirmed = await _confirmDestructive(
      context,
      title: 'Delete this task?',
      message: 'This permanently removes "${task.title}" along with its '
          'notes and comments. This cannot be undone.',
      confirmLabel: 'Delete task',
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteTask(task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Task deleted.')));
      // Hand the id back so whoever opened this screen — a task list, or the
      // parent task's subtask list — can drop the row straight away instead
      // of showing it until their own refetch lands.
      Navigator.of(context).pop(task.id);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _editNote(TaskNote note) async {
    final body = await _promptForBody(
      context,
      title: 'Edit note',
      label: 'Note',
      initialValue: note.body,
    );
    if (body == null) return;
    try {
      await widget.controller.updateNote(noteId: note.id, body: body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note updated.')));
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _deleteNote(TaskNote note) async {
    final confirmed = await _confirmDestructive(
      context,
      title: 'Delete this note?',
      message: 'The note will be permanently removed.',
      confirmLabel: 'Delete note',
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteNote(note.id);
      if (!mounted) return;
      // Drop it from the cached detail first so it vanishes immediately…
      _removeNote(note.id);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note deleted.')));
      // …then reconcile against the server.
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _editComment(TaskComment comment) async {
    final body = await _promptForBody(
      context,
      title: 'Edit comment',
      label: 'Comment',
      initialValue: comment.body,
    );
    if (body == null) return;
    try {
      await widget.controller
          .updateComment(commentId: comment.id, body: body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Comment updated.')));
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  /// Deleting a comment cascades its replies server-side, so the confirmation
  /// says how many would go with it (counted from the loaded thread).
  Future<void> _deleteComment(TaskComment comment) async {
    // Capture the subtree before the delete: afterwards these rows are gone
    // server-side, and we need the ids to clear them from the UI in one go.
    final doomed = _descendantCommentIds(comment.id);
    final replies = doomed.length;
    final confirmed = await _confirmDestructive(
      context,
      title: 'Delete this comment?',
      message: replies == 0
          ? 'The comment will be permanently removed.'
          : 'This also deletes $replies '
              '${replies == 1 ? 'reply' : 'replies'} underneath it. This '
              'cannot be undone.',
      confirmLabel: 'Delete comment',
    );
    if (confirmed != true) return;
    try {
      final deletedReplies = await widget.controller.deleteComment(comment.id);
      if (!mounted) return;
      _removeComment(comment.id, doomed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedReplies == 0
                ? 'Comment deleted.'
                : 'Comment and $deletedReplies '
                    '${deletedReplies == 1 ? 'reply' : 'replies'} deleted.',
          ),
        ),
      );
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  /// Ids of every comment nested anywhere beneath [commentId] in the loaded
  /// thread. Used to word the delete confirmation and to drop the whole
  /// subtree from the UI at once, since the server cascades replies.
  Set<int> _descendantCommentIds(int commentId) {
    final comments = _lastLoaded?.comments ?? const <TaskComment>[];
    final found = <int>{};
    var frontier = <int>{commentId};
    while (frontier.isNotEmpty) {
      final next = <int>{};
      for (final comment in comments) {
        if (comment.parentCommentId != null &&
            frontier.contains(comment.parentCommentId) &&
            found.add(comment.id)) {
          next.add(comment.id);
        }
      }
      frontier = next;
    }
    return found;
  }

  // --- Optimistic removal ---------------------------------------------------
  // Mirrors _insertNote / _insertComment: drop the record from the cached
  // detail the moment the server confirms the delete, so it disappears at
  // once instead of lingering until the follow-up /task/detail round-trip
  // lands. The reload that follows reconciles against the server's copy.

  void _removeNote(int noteId) {
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task,
        subtasks: current.subtasks,
        notes: current.notes
            .where((note) => note.id != noteId)
            .toList(growable: false),
        comments: current.comments,
      );
    });
  }

  /// Removes [commentId] together with [doomed] — the replies the server
  /// cascaded away with it — so no orphaned subtree is left on screen.
  void _removeComment(int commentId, Set<int> doomed) {
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task,
        subtasks: current.subtasks,
        notes: current.notes,
        comments: current.comments
            .where((comment) =>
                comment.id != commentId && !doomed.contains(comment.id))
            .toList(growable: false),
      );
    });
  }

  /// Swap a freshly-updated task into the cached detail — either this screen's
  /// own task or one of its subtask rows — so a status change or an edit is
  /// visible the moment the server confirms it, instead of after the
  /// follow-up /task/detail round-trip. Also notifies whoever opened this
  /// screen so their list row updates at the same time.
  void _applyTask(Task updated) {
    widget.onTaskChanged?.call(updated);
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task.id == updated.id ? updated : current.task,
        subtasks: current.subtasks
            .map((subtask) => subtask.id == updated.id ? updated : subtask)
            .toList(growable: false),
        notes: current.notes,
        comments: current.comments,
      );
    });
  }

  void _removeSubtask(int subtaskId) {
    final current = _lastLoaded;
    if (current == null) return;
    setState(() {
      _lastLoaded = TaskDetail(
        task: current.task,
        subtasks: current.subtasks
            .where((subtask) => subtask.id != subtaskId)
            .toList(growable: false),
        notes: current.notes,
        comments: current.comments,
      );
    });
  }

  void _showError(Object error) {
    final message =
        error is AuthApiException ? error.message : 'Something went wrong.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSubtask(Task subtask) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<int?>(
            builder: (_) => TaskDetailScreen(
              controller: widget.controller,
              taskId: subtask.id,
              usersById: widget.usersById,
              projectsById: widget.projectsById,
              // Keep this screen's subtask row in step while the child screen
              // is open, so returning never shows a stale status.
              onTaskChanged: _applyTask,
            ),
          ),
        )
        // Returning may have changed this task's children/status. A non-null
        // result is the id of a subtask deleted down there, so drop it from
        // the list immediately rather than waiting for the refetch.
        .then((deletedId) {
      if (!mounted) return;
      if (deletedId != null) _removeSubtask(deletedId);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<TaskDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasData) _lastLoaded = snapshot.data;
          final detail = snapshot.hasData ? snapshot.data! : _lastLoaded;
          final refreshing =
              snapshot.connectionState == ConnectionState.waiting;

          // Nothing to show yet: first load, or an error before any data.
          if (detail == null) {
            if (refreshing) {
              return const Center(child: CircularProgressIndicator());
            }
            return _CenteredCard(
              message: snapshot.error is AuthApiException
                  ? (snapshot.error as AuthApiException).message
                  : 'Could not load this task.',
              action: FilledButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }

          final task = detail.task;
          // A task may have multiple assignees; any one of them can edit.
          final assignees = task.assigneeIds.isNotEmpty
              ? task.assigneeIds
              : (task.assigneeId == null ? const <int>[] : [task.assigneeId!]);
          final canEdit = _myId != null && assignees.contains(_myId);
          final canChangeStatus = _myId != null &&
              (assignees.contains(_myId) || task.createdById == _myId);
          // Mirrors the backend rule: creator or assignee may edit the task,
          // creator alone may delete it. Hiding the controls is a convenience
          // — the server answers 403 either way.
          final canEditTask = _myId != null &&
              (assignees.contains(_myId) || task.createdById == _myId);
          final canDeleteTask = _myId != null && task.createdById == _myId;
          final projectName = task.projectId == null
              ? null
              : widget.projectsById[task.projectId!]?.name;
          final assigneesLabel = assignees.isEmpty
              ? 'Unassigned'
              : assignees.map(_userLabel).join(' · ');

          return Column(
            children: [
              // Thin top bar while re-fetching, so the page stays visible.
              SizedBox(
                height: 3,
                child: refreshing ? const LinearProgressIndicator() : null,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _HeaderCard(
                          task: task,
                          assigneeLabel: assigneesLabel,
                          createdByLabel: _userLabel(task.createdById),
                          projectName: projectName,
                          canChangeStatus: canChangeStatus,
                          onChangeStatus: () => _changeStatus(task),
                          canEditTask: canEditTask,
                          canDeleteTask: canDeleteTask,
                          onEditTask: () => _editTask(task),
                          onDeleteTask: () => _deleteTask(task),
                          // Same rule as editing: creator or assignee. The
                          // server re-checks.
                          canRaiseBlocker: canEditTask,
                          onRaiseBlocker: () => _raiseBlocker(task),
                        ),
                        const SizedBox(height: 20),
                        _SubtasksSection(
                          subtasks: detail.subtasks,
                          canAdd: canEdit,
                          onAdd: () => _addSubtask(task),
                          onOpen: _openSubtask,
                          assigneeLabel: _userLabel,
                        ),
                        const SizedBox(height: 20),
                        _NotesSection(
                          notes: detail.notes,
                          canAdd: canEdit,
                          authorLabel: _userLabel,
                          currentUserId: _myId,
                          onEditNote: _editNote,
                          onDeleteNote: _deleteNote,
                          onAdd: (body) async {
                            try {
                              final note = await widget.controller
                                  .addNote(taskId: task.id, body: body);
                              // Optimistically append so it shows up instantly
                              // — the full re-fetch confirms it moments later.
                              _insertNote(note);
                              _reload();
                              return true;
                            } catch (error) {
                              if (mounted) _showError(error);
                              return false;
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                        _CommentsSection(
                          comments: detail.comments,
                          taskId: task.id,
                          controller: widget.controller,
                          currentUserId: _myId,
                          authorLabel: _userLabel,
                          onEditComment: _editComment,
                          onDeleteComment: _deleteComment,
                          onCommentPosted: (posted) {
                            // Show the new comment in place right away…
                            _insertComment(posted);
                            // …then fetch the server's canonical copy so the
                            // ids/timestamps reconcile.
                            _reload();
                          },
                        ),
                      ],
                    ),
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

/// Yes/no confirmation for an irreversible action. Returns true only when the
/// user explicitly confirms; dismissing returns null.
Future<bool?> _confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Small single-field editor used for note and comment bodies. Returns the
/// trimmed text, or null when cancelled or left unchanged.
Future<String?> _promptForBody(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Treat "saved without changing anything" as a no-op so we skip the
    // round-trip and the version bump.
    if (result == null || result == initialValue.trim()) return null;
    return result;
  } finally {
    controller.dispose();
  }
}

/// Edit/delete overflow menu shown on a task, note or comment the signed-in
/// user owns. Hidden entirely when they own neither action.
class _OwnerActions extends StatelessWidget {
  const _OwnerActions({
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
    this.tooltip = 'More actions',
    this.dense = false,
  });

  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String tooltip;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: dense ? 18 : 24),
      constraints: dense ? const BoxConstraints(minWidth: 140) : null,
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined, size: 20),
              title: Text('Edit'),
            ),
          ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, size: 20, color: error),
              title: Text('Delete', style: TextStyle(color: error)),
            ),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.task,
    required this.assigneeLabel,
    required this.createdByLabel,
    required this.projectName,
    required this.canChangeStatus,
    required this.onChangeStatus,
    required this.canEditTask,
    required this.canDeleteTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.canRaiseBlocker,
    required this.onRaiseBlocker,
  });

  final Task task;
  final String assigneeLabel;
  final String createdByLabel;
  final String? projectName;
  final bool canChangeStatus;
  final VoidCallback onChangeStatus;
  final bool canEditTask;
  final bool canDeleteTask;
  final VoidCallback onEditTask;
  final VoidCallback onDeleteTask;
  final bool canRaiseBlocker;
  final VoidCallback onRaiseBlocker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _OwnerActions(
                  canEdit: canEditTask,
                  canDelete: canDeleteTask,
                  onEdit: onEditTask,
                  onDelete: onDeleteTask,
                  tooltip: 'Task actions',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TaskStatusChip(status: task.status),
                if (projectName != null)
                  TagChip(label: 'Project: $projectName'),
                TagChip(label: 'Type: ${task.type.label}'),
                TagChip(label: 'Discipline: ${task.discipline.label}'),
                if (canChangeStatus)
                  OutlinedButton.icon(
                    onPressed: onChangeStatus,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Change status'),
                  ),
                if (canRaiseBlocker)
                  OutlinedButton.icon(
                    onPressed: onRaiseBlocker,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: const Text('Blocker'),
                  ),
              ],
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(task.description!, style: theme.textTheme.bodyLarge),
            ],
            const Divider(height: 32),
            _MetaRow(
              icon: Icons.person_outline,
              label: 'Assigned to',
              value: assigneeLabel,
            ),
            const SizedBox(height: 10),
            _MetaRow(
              icon: Icons.badge_outlined,
              label: 'Assigned by',
              value: createdByLabel,
            ),
            if (task.startAt != null) ...[
              const SizedBox(height: 10),
              _MetaRow(
                icon: Icons.play_circle_outline,
                label: 'Starts',
                value: formatTaskDate(task.startAt!),
              ),
            ],
            if (task.dueAt != null) ...[
              const SizedBox(height: 10),
              _MetaRow(
                icon: Icons.event_outlined,
                label: 'Due',
                value: formatTaskDate(task.dueAt!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: Text(label, style: TextStyle(color: muted, fontSize: 13)),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _SubtasksSection extends StatelessWidget {
  const _SubtasksSection({
    required this.subtasks,
    required this.canAdd,
    required this.onAdd,
    required this.onOpen,
    required this.assigneeLabel,
  });

  final List<Task> subtasks;
  final bool canAdd;
  final VoidCallback onAdd;
  final void Function(Task) onOpen;
  final String Function(int?) assigneeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subtasks (${subtasks.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (canAdd)
                  FilledButton.tonalIcon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add subtask'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (subtasks.isEmpty)
              Text(
                canAdd
                    ? 'No subtasks yet. Break this down with "Add subtask".'
                    : 'No subtasks yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final subtask in subtasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SubtaskTile(
                    subtask: subtask,
                    assigneeLabel: assigneeLabel(subtask.assigneeId),
                    onTap: () => onOpen(subtask),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SubtaskTile extends StatelessWidget {
  const _SubtaskTile({
    required this.subtask,
    required this.assigneeLabel,
    required this.onTap,
  });

  final Task subtask;
  final String assigneeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtask.title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    assigneeLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (subtask.type != TaskType.decide ||
                      subtask.discipline != TaskDiscipline.decide ||
                      subtask.dueAt != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (subtask.type != TaskType.decide)
                          TagChip(label: subtask.type.label),
                        if (subtask.discipline != TaskDiscipline.decide)
                          TagChip(label: subtask.discipline.label),
                        if (subtask.dueAt != null)
                          TagChip(
                            label: 'Due ${formatTaskDate(subtask.dueAt!)}',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            TaskStatusChip(status: subtask.status),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _NotesSection extends StatefulWidget {
  const _NotesSection({
    required this.notes,
    required this.canAdd,
    required this.authorLabel,
    required this.currentUserId,
    required this.onEditNote,
    required this.onDeleteNote,
    required this.onAdd,
  });

  final List<TaskNote> notes;
  final bool canAdd;
  final String Function(int?) authorLabel;

  /// Signed-in user; a note is editable/deletable only by its author.
  final int? currentUserId;
  final void Function(TaskNote) onEditNote;
  final void Function(TaskNote) onDeleteNote;

  /// Returns true when the note was created (so the field can clear).
  final Future<bool> Function(String body) onAdd;

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    // Empty the field the instant the user hits send, the way a chat
    // composer should, rather than after the round-trip — the posted note
    // already appears optimistically. The text is put back only if the post
    // fails, so nothing is lost on a 403 or a dropped connection.
    _controller.clear();
    setState(() => _sending = true);
    final ok = await widget.onAdd(body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) _controller.text = body;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes (${widget.notes.length})',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (widget.notes.isEmpty)
              Text(
                'No notes yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final note in widget.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _NoteTile(
                    note: note,
                    authorLabel: widget.authorLabel(note.authorId),
                    isMine: widget.currentUserId != null &&
                        note.authorId == widget.currentUserId,
                    onEdit: () => widget.onEditNote(note),
                    onDelete: () => widget.onDeleteNote(note),
                  ),
                ),
            if (widget.canAdd) ...[
              const Divider(height: 28),
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                maxLength: 4000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Add a note',
                  hintText: 'Share an update on this task…',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: const Text('Post note'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.authorLabel,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskNote note;
  final String authorLabel;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  authorLabel,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (note.createdAt != null)
                Text(
                  formatTaskDate(note.createdAt!),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              _OwnerActions(
                canEdit: isMine,
                canDelete: isMine,
                onEdit: onEdit,
                onDelete: onDelete,
                tooltip: 'Note actions',
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.body, style: theme.textTheme.bodyMedium),
          if (note.updatedAt != null &&
              note.createdAt != null &&
              note.updatedAt!.isAfter(note.createdAt!)) ...[
            const SizedBox(height: 4),
            Text(
              'Edited ${formatTaskDate(note.updatedAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Threaded discussion. The server returns a flat list with
/// [TaskComment.parentCommentId]; this widget builds the tree and renders
/// each level with a leading indent plus a left guide line so nested replies
/// stay visibly nested (a reply to a reply sits one level deeper, not
/// alongside its parent). Anyone can comment; the task's assignees and the
/// parent-comment author get notified server-side.
class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.comments,
    required this.taskId,
    required this.controller,
    required this.currentUserId,
    required this.authorLabel,
    required this.onEditComment,
    required this.onDeleteComment,
    required this.onCommentPosted,
  });

  final List<TaskComment> comments;
  final int taskId;
  final AuthController controller;
  final int? currentUserId;
  final String Function(int?) authorLabel;
  /// A comment may be edited or deleted only by its author; deleting one also
  /// cascades its replies server-side.
  final void Function(TaskComment) onEditComment;
  final void Function(TaskComment) onDeleteComment;
  /// Called with the comment the server just created so the parent can
  /// insert it optimistically and then reload.
  final ValueChanged<TaskComment> onCommentPosted;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _topLevelController = TextEditingController();
  bool _sendingTopLevel = false;

  /// The comment we are currently replying to, if any. Clicking Reply on a
  /// nested comment arms this; the composer below the thread then targets it.
  int? _replyingTo;
  final _replyController = TextEditingController();
  bool _sendingReply = false;

  @override
  void dispose() {
    _topLevelController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  /// Posts [body] with [parentCommentId] and clears the matching text field
  /// on success. Any failure is surfaced via the snackbar so the composer
  /// keeps the typed text for a retry.
  Future<bool> _post({required String body, int? parentCommentId}) async {
    try {
      final posted = await widget.controller.addComment(
        taskId: widget.taskId,
        body: body,
        parentCommentId: parentCommentId,
      );
      widget.onCommentPosted(posted);
      return true;
    } catch (error) {
      if (!mounted) return false;
      final message =
          error is AuthApiException ? error.message : 'Could not post.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }

  Future<void> _sendTopLevel() async {
    final body = _topLevelController.text.trim();
    if (body.isEmpty) return;
    // Clear up front — see the note in _NotesSectionState._send.
    _topLevelController.clear();
    setState(() => _sendingTopLevel = true);
    final ok = await _post(body: body);
    if (!mounted) return;
    setState(() => _sendingTopLevel = false);
    if (!ok) _topLevelController.text = body;
  }

  Future<void> _sendReply() async {
    final target = _replyingTo;
    final body = _replyController.text.trim();
    if (target == null || body.isEmpty) return;
    // Close the inline reply composer and empty it immediately; the reply
    // itself shows up optimistically in the thread. On failure we re-arm it
    // with the original text so the user can retry without retyping.
    _replyController.clear();
    setState(() {
      _sendingReply = true;
      _replyingTo = null;
    });
    final ok = await _post(body: body, parentCommentId: target);
    if (!mounted) return;
    setState(() {
      _sendingReply = false;
      if (!ok) {
        _replyingTo = target;
        _replyController.text = body;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Group comments by parent id so the tree can be built in one pass.
    final childrenByParent = <int?, List<TaskComment>>{};
    for (final comment in widget.comments) {
      childrenByParent
          .putIfAbsent(comment.parentCommentId, () => [])
          .add(comment);
    }
    final topLevel = childrenByParent[null] ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forum_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(
                  'Comments (${widget.comments.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (topLevel.isEmpty)
              Text(
                'No comments yet. Start the discussion below.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final comment in topLevel)
                _CommentNode(
                  comment: comment,
                  childrenByParent: childrenByParent,
                  depth: 0,
                  authorLabel: widget.authorLabel,
                  currentUserId: widget.currentUserId,
                  onEditComment: widget.onEditComment,
                  onDeleteComment: widget.onDeleteComment,
                  replyingTo: _replyingTo,
                  onReplyPressed: (id) => setState(() {
                    _replyingTo = id;
                    _replyController.clear();
                  }),
                  onCancelReply: () => setState(() {
                    _replyingTo = null;
                    _replyController.clear();
                  }),
                  replyController: _replyController,
                  sendingReply: _sendingReply,
                  onSendReply: _sendReply,
                ),
            const Divider(height: 28),
            Text(
              'Add a comment',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _topLevelController,
              minLines: 2,
              maxLines: 4,
              maxLength: 4000,
              decoration: const InputDecoration(
                hintText: 'Write a comment… assignees will be notified.',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _sendingTopLevel ? null : _sendTopLevel,
                icon: _sendingTopLevel
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Post comment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders one comment plus its replies recursively. Each level adds a
/// leading indent and a left guide line so a reply of a reply sits one step
/// deeper than its parent, which is in turn one step deeper than the
/// top-level comment it answers.
class _CommentNode extends StatelessWidget {
  const _CommentNode({
    required this.comment,
    required this.childrenByParent,
    required this.depth,
    required this.authorLabel,
    required this.currentUserId,
    required this.onEditComment,
    required this.onDeleteComment,
    required this.replyingTo,
    required this.onReplyPressed,
    required this.onCancelReply,
    required this.replyController,
    required this.sendingReply,
    required this.onSendReply,
  });

  final TaskComment comment;
  final Map<int?, List<TaskComment>> childrenByParent;
  final int depth;
  final String Function(int?) authorLabel;
  final int? currentUserId;
  final void Function(TaskComment) onEditComment;
  final void Function(TaskComment) onDeleteComment;
  final int? replyingTo;
  final ValueChanged<int> onReplyPressed;
  final VoidCallback onCancelReply;
  final TextEditingController replyController;
  final bool sendingReply;
  final Future<void> Function() onSendReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = childrenByParent[comment.id] ?? const <TaskComment>[];
    final isReplyTarget = replyingTo == comment.id;
    final isMine =
        currentUserId != null && comment.authorId == currentUserId;
    // Cap the visual indent so deeply nested chains stay readable on narrow
    // viewports; nesting still reads via the guide line and spacing even
    // when the pixel offset stops growing.
    final indentDepth = depth > 6 ? 6 : depth;
    final leftPad = 16.0 * indentDepth;
    return Padding(
      padding: EdgeInsets.only(left: leftPad, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (depth > 0)
                  Container(
                    width: 2,
                    margin: const EdgeInsets.only(right: 10),
                    color: theme.colorScheme.outlineVariant,
                  ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                authorLabel(comment.authorId),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (comment.createdAt != null)
                              Text(
                                formatTaskDate(comment.createdAt!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            _OwnerActions(
                              canEdit: isMine,
                              canDelete: isMine,
                              onEdit: () => onEditComment(comment),
                              onDelete: () => onDeleteComment(comment),
                              tooltip: 'Comment actions',
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(comment.body,
                            style: theme.textTheme.bodyMedium),
                        if (comment.updatedAt != null &&
                            comment.createdAt != null &&
                            comment.updatedAt!
                                .isAfter(comment.createdAt!)) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Edited ${formatTaskDate(comment.updatedAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: const Size(0, 32),
                            ),
                            onPressed: isReplyTarget
                                ? onCancelReply
                                : () => onReplyPressed(comment.id),
                            icon: Icon(
                              isReplyTarget ? Icons.close : Icons.reply,
                              size: 16,
                            ),
                            label: Text(isReplyTarget ? 'Cancel' : 'Reply'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isReplyTarget)
            Padding(
              // One extra indent step so the composer sits where the new
              // reply will land once posted.
              padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: replyController,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: InputDecoration(
                      hintText:
                          'Reply to ${authorLabel(comment.authorId)}…',
                      isDense: true,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: sendingReply ? null : onSendReply,
                      icon: sendingReply
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Post reply'),
                    ),
                  ),
                ],
              ),
            ),
          // Recurse: each child renders one step deeper than this comment.
          for (final child in children)
            _CommentNode(
              comment: child,
              childrenByParent: childrenByParent,
              depth: depth + 1,
              authorLabel: authorLabel,
              currentUserId: currentUserId,
              onEditComment: onEditComment,
              onDeleteComment: onDeleteComment,
              replyingTo: replyingTo,
              onReplyPressed: onReplyPressed,
              onCancelReply: onCancelReply,
              replyController: replyController,
              sendingReply: sendingReply,
              onSendReply: onSendReply,
            ),
        ],
      ),
    );
  }
}

class _CenteredCard extends StatelessWidget {
  const _CenteredCard({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: Theme.of(context).textTheme.titleMedium),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Raise a blocker: pick the member holding the task up and say why. On
/// submit the task is flagged `blocked` and that member gets an alert — a
/// modal popup straight away if they have a tab open, replayed on their next
/// connect if not. Pops the updated task so the caller can repaint.
class _RaiseBlockerDialog extends StatefulWidget {
  const _RaiseBlockerDialog({
    required this.controller,
    required this.task,
    required this.candidates,
  });

  final AuthController controller;
  final Task task;

  /// Everyone who could be named — the signed-in user is already excluded.
  final List<AuthUser> candidates;

  @override
  State<_RaiseBlockerDialog> createState() => _RaiseBlockerDialogState();
}

class _RaiseBlockerDialogState extends State<_RaiseBlockerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  int? _responsibleId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the only candidate when there is exactly one, so the common
    // two-person case is a single tap.
    if (widget.candidates.length == 1) {
      _responsibleId = widget.candidates.first.id;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final responsibleId = _responsibleId;
    if (responsibleId == null) {
      setState(() => _error = 'Choose who is blocking this task.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.controller.raiseBlocker(
        taskId: widget.task.id,
        responsibleUserId: responsibleId,
        message: _messageController.text.trim(),
      );
      if (mounted) Navigator.pop(context, updated);
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
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.report_problem_outlined, color: theme.colorScheme.error),
      title: const Text('Raise a blocker'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.task.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _responsibleId,
                  decoration: const InputDecoration(
                    labelText: 'Who is blocking this?',
                  ),
                  items: [
                    for (final user in widget.candidates)
                      DropdownMenuItem<int>(
                        value: user.id,
                        child: Text('${user.displayName} · ${user.employeeId}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _responsibleId = value),
                  validator: (value) =>
                      value == null ? 'Choose a member' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _messageController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'What is blocked, and what do you need?',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Describe the blocker';
                    if (text.length > 4000) {
                      return 'Message must be 4000 characters or fewer';
                    }
                    return null;
                  },
                ),
                Text(
                  'This sets the task to Blocked and alerts them right away.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Raise blocker'),
        ),
      ],
    );
  }
}

/// Edit an existing task. Pre-filled from [task]; the form submits every
/// field it manages, and emptying an optional one sends an explicit null so
/// the server clears it. Shown to the task's creator and to its assignees —
/// the backend re-checks that on every call.
class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog({
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
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late TaskStatus _status;
  late TaskType _type;
  late TaskDiscipline _discipline;
  late Set<int> _assigneeIds;
  late int? _projectId;
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;

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
    // Only offer a project the picker actually knows about, so an unknown id
    // doesn't crash the dropdown's value lookup.
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

  Future<void> _chooseStartDate() async {
    final today = DateTime.now();
    final initial = _startDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Wide bounds: an existing task may already carry a past date, and the
      // picker throws if initialDate falls outside the range.
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _chooseDueDate() async {
    final today = DateTime.now();
    final initial = _dueDate ?? _startDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year - 5),
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
    final description = _descriptionController.text.trim();
    try {
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Edit task'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
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
                  minLines: 2,
                  maxLines: 4,
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
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<TaskDiscipline>(
                  initialValue: _discipline,
                  decoration: const InputDecoration(labelText: 'Discipline'),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Assigned to',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.users.isEmpty)
                  Text(
                    'No teammates available.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
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
                  Text(
                    'Saving with nobody selected leaves this task unassigned.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _chooseStartDate,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(
                    _startDate == null
                        ? 'Start date (optional)'
                        : 'Starts ${formatTaskDate(_startDate!)}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _chooseDueDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _dueDate == null
                        ? 'Due date (optional)'
                        : 'Due ${formatTaskDate(_dueDate!)}',
                  ),
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
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          // Pops null — the caller treats that as "nothing changed".
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
              : const Text('Save changes'),
        ),
      ],
    );
  }
}

/// Dialog to create a subtask under [parent]. Only shown to the assignee.
class _AddSubtaskDialog extends StatefulWidget {
  const _AddSubtaskDialog({
    required this.controller,
    required this.parent,
    required this.users,
  });

  final AuthController controller;
  final Task parent;
  final List<AuthUser> users;

  @override
  State<_AddSubtaskDialog> createState() => _AddSubtaskDialogState();
}

class _AddSubtaskDialogState extends State<_AddSubtaskDialog> {
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
      await widget.controller.createSubtask(
        parentTaskId: widget.parent.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
        type: _type,
        discipline: _discipline,
        startAt: _startDate,
        dueAt: _dueDate,
        assigneeIds: _assigneeId == null ? const [] : [_assigneeId!],
      );
      if (mounted) Navigator.pop(context, true);
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
      title: const Text('Add subtask'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
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
                  minLines: 2,
                  maxLines: 4,
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
                  decoration: const InputDecoration(labelText: 'Discipline'),
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
                OutlinedButton.icon(
                  onPressed: _chooseStartDate,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(
                    _startDate == null
                        ? 'Start date (optional)'
                        : 'Starts ${formatTaskDate(_startDate!)}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _chooseDueDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _dueDate == null
                        ? 'Due date (optional)'
                        : 'Due ${formatTaskDate(_dueDate!)}',
                  ),
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
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
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
