import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../common/error_messages.dart';
import '../common/snackbar.dart';
import '../common/widgets/confirm_dialog.dart';
import '../common/widgets/message_card.dart';
import '../common/widgets/pane_scaffold.dart';
import '../common/widgets/refresh_bar.dart';
import '../common/widgets/text_prompt_dialog.dart';
import '../tasks/task_models.dart';
import '../tasks/task_permissions.dart';
import '../tasks/user_directory.dart';
import 'task_detail/comments_section.dart';
import 'task_detail/dialogs/add_subtask_dialog.dart';
import 'task_detail/dialogs/edit_task_dialog.dart';
import 'task_detail/dialogs/raise_blocker_dialog.dart';
import 'task_detail/dialogs/status_picker_dialog.dart';
import 'task_detail/notes_section.dart';
import 'task_detail/subtasks_section.dart';
import 'task_detail/task_header_card.dart';

/// Full-screen view of a single task: header + status control, its direct
/// subtasks, notes, and threaded comments.
///
/// Opened via `Navigator.push` (the app has no router by design) and pops
/// the task's id if it was deleted here, so the opener can drop that row at
/// once. Permissions are convenience gates — the backend re-enforces them.
///
/// Every mutation patches the cached [TaskDetail] the moment the server
/// confirms it, then refetches to reconcile; the refetch is never what makes
/// a change visible.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.controller,
    required this.taskId,
    required this.directory,
    this.projectsById = const {},
    this.onTaskChanged,
  });

  final AuthController controller;
  final int taskId;
  final UserDirectory directory;
  final Map<int, Project> projectsById;

  /// Fired with the server's updated task whenever its status is changed or
  /// it is edited here, so the opener (a task list, or a parent task's
  /// subtask list) refreshes that row at the same moment.
  final ValueChanged<Task>? onTaskChanged;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  /// What is on screen. Patched optimistically by mutations and replaced by
  /// each completed fetch; kept through a refetch so the page never blanks.
  TaskDetail? _detail;
  Object? _loadError;
  bool _loading = true;

  /// Only the newest fetch may write [_detail]: an older response landing
  /// late would otherwise overwrite fresher local patches.
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  int? get _myId => widget.controller.currentUser?.id;

  void _reload() {
    setState(() => _loading = true);
    _fetch();
  }

  Future<void> _fetch() async {
    final generation = ++_fetchGeneration;
    try {
      final detail = await widget.controller.taskDetail(widget.taskId);
      if (!mounted || generation != _fetchGeneration) return;
      setState(() {
        _detail = detail;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _fetchGeneration) return;
      // With data already on screen it stays visible; the error only shows
      // when there is nothing else to show.
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  // --- Local patches ---------------------------------------------------------

  void _patch(TaskDetail Function(TaskDetail detail) update) {
    final current = _detail;
    if (current == null) return;
    setState(() => _detail = update(current));
  }

  /// Swaps a freshly-updated task into the cache — this screen's own task or
  /// one of its subtask rows — and tells the opener, so its row matches.
  void _applyTask(Task updated) {
    widget.onTaskChanged?.call(updated);
    _patch((detail) => detail.copyWith(
          task: detail.task.id == updated.id ? updated : detail.task,
          subtasks: [
            for (final subtask in detail.subtasks)
              subtask.id == updated.id ? updated : subtask,
          ],
        ));
  }

  // --- Request plumbing ------------------------------------------------------

  /// Runs [request]. On success: shows [successMessage], applies [onSuccess]
  /// (the local patch), then refetches unless [reload] is false. On failure:
  /// shows the error. Resolves to whether the request succeeded.
  Future<bool> _mutate<T>(
    Future<T> Function() request, {
    void Function(T result)? onSuccess,
    String Function(T result)? successMessage,
    bool reload = true,
    String errorFallback = 'Something went wrong.',
  }) async {
    try {
      final result = await request();
      if (!mounted) return true;
      if (successMessage != null) {
        context.showSnackMessage(successMessage(result));
      }
      onSuccess?.call(result);
      if (reload) _reload();
      return true;
    } catch (error) {
      if (mounted) {
        context.showSnackMessage(errorMessage(error, fallback: errorFallback));
      }
      return false;
    }
  }

  /// Follow-up for a dialog that already saved and popped the updated task.
  void _afterTaskSaved(Task updated, String message) {
    _applyTask(updated);
    context.showSnackMessage(message);
    _reload();
  }

  // --- Task actions ------------------------------------------------------------

  Future<void> _changeStatus(Task task) async {
    final picked = await showStatusPicker(context, current: task.status);
    if (picked == null || picked == task.status) return;
    await _mutate(
      () => widget.controller.changeTaskStatus(taskId: task.id, status: picked),
      onSuccess: _applyTask,
      successMessage: (_) => 'Status set to ${picked.label}.',
    );
  }

  Future<void> _editTask(Task task) async {
    final updated = await showDialog<Task>(
      context: context,
      builder: (context) => EditTaskDialog(
        controller: widget.controller,
        task: task,
        users: widget.directory.users,
        projects: widget.projectsById.values.toList(growable: false),
      ),
    );
    if (updated != null && mounted) _afterTaskSaved(updated, 'Task updated.');
  }

  /// Flags the task as blocked on another member, who is alerted at once if
  /// they have a tab open, and on their next connect otherwise.
  Future<void> _raiseBlocker(Task task) async {
    final candidates = widget.directory.users
        // Flagging yourself is meaningless, and the server rejects it.
        .where((user) => user.id != _myId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      context.showSnackMessage('No other members to flag.');
      return;
    }
    final updated = await showDialog<Task>(
      context: context,
      builder: (context) => RaiseBlockerDialog(
        controller: widget.controller,
        task: task,
        candidates: candidates,
      ),
    );
    if (updated != null && mounted) {
      _afterTaskSaved(updated, 'Blocker raised. They have been notified.');
    }
  }

  /// Deletes the task and leaves the screen. The server refuses while
  /// subtasks remain, and that message is surfaced verbatim.
  Future<void> _deleteTask(Task task) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this task?',
      message: 'This permanently removes "${task.title}" along with its '
          'notes and comments. This cannot be undone.',
      confirmLabel: 'Delete task',
    );
    if (confirmed != true || !mounted) return;
    await _mutate(
      () => widget.controller.deleteTask(task.id),
      successMessage: (_) => 'Task deleted.',
      reload: false,
      // Hand the id back so the opener drops the row straight away.
      onSuccess: (_) => Navigator.of(context).pop(task.id),
    );
  }

  // --- Subtasks ----------------------------------------------------------------

  Future<void> _addSubtask(Task parent) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AddSubtaskDialog(
        controller: widget.controller,
        parent: parent,
        users: widget.directory.users,
      ),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _openSubtask(Task subtask) async {
    final deletedId = await Navigator.of(context).push<int?>(
      MaterialPageRoute<int?>(
        builder: (_) => TaskDetailScreen(
          controller: widget.controller,
          taskId: subtask.id,
          directory: widget.directory,
          projectsById: widget.projectsById,
          // Keeps this screen's subtask row in step while the child is open.
          onTaskChanged: _applyTask,
        ),
      ),
    );
    if (!mounted) return;
    if (deletedId != null) {
      _patch((detail) => detail.copyWith(
            subtasks: detail.subtasks
                .where((subtask) => subtask.id != deletedId)
                .toList(growable: false),
          ));
    }
    // The child may have changed this task's children or status.
    _reload();
  }

  // --- Notes -------------------------------------------------------------------

  Future<bool> _addNote(Task task, String body) {
    return _mutate(
      () => widget.controller.addNote(taskId: task.id, body: body),
      // Notes come back oldest-first, so append.
      onSuccess: (note) =>
          _patch((detail) => detail.copyWith(notes: [...detail.notes, note])),
    );
  }

  Future<void> _editNote(TaskNote note) async {
    final body = await promptForText(
      context,
      title: 'Edit note',
      label: 'Note',
      initialValue: note.body,
    );
    if (body == null) return;
    await _mutate(
      () => widget.controller.updateNote(noteId: note.id, body: body),
      successMessage: (_) => 'Note updated.',
    );
  }

  Future<void> _deleteNote(TaskNote note) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this note?',
      message: 'The note will be permanently removed.',
      confirmLabel: 'Delete note',
    );
    if (confirmed != true) return;
    await _mutate(
      () => widget.controller.deleteNote(note.id),
      successMessage: (_) => 'Note deleted.',
      onSuccess: (_) => _patch((detail) => detail.copyWith(
            notes: detail.notes
                .where((item) => item.id != note.id)
                .toList(growable: false),
          )),
    );
  }

  // --- Comments ----------------------------------------------------------------

  Future<bool> _postComment(
    Task task,
    String body, {
    int? parentCommentId,
  }) {
    return _mutate(
      () => widget.controller.addComment(
        taskId: task.id,
        body: body,
        parentCommentId: parentCommentId,
      ),
      // Comments are flat and oldest-first; the section threads them by
      // parent id, so appending slots a reply into the right place.
      onSuccess: (comment) => _patch(
        (detail) => detail.copyWith(comments: [...detail.comments, comment]),
      ),
      errorFallback: 'Could not post.',
    );
  }

  Future<void> _editComment(TaskComment comment) async {
    final body = await promptForText(
      context,
      title: 'Edit comment',
      label: 'Comment',
      initialValue: comment.body,
    );
    if (body == null) return;
    await _mutate(
      () => widget.controller.updateComment(commentId: comment.id, body: body),
      successMessage: (_) => 'Comment updated.',
    );
  }

  /// Deleting a comment cascades its replies server-side, so the confirmation
  /// says how many go with it and the whole subtree leaves the UI at once.
  Future<void> _deleteComment(TaskComment comment) async {
    // Captured before the delete: afterwards those rows are gone server-side.
    final doomed = _detail?.replyIdsUnder(comment.id) ?? const <int>{};
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this comment?',
      message: doomed.isEmpty
          ? 'The comment will be permanently removed.'
          : 'This also deletes ${_replies(doomed.length)} underneath it. '
              'This cannot be undone.',
      confirmLabel: 'Delete comment',
    );
    if (confirmed != true) return;
    await _mutate(
      () => widget.controller.deleteComment(comment.id),
      successMessage: (deletedReplies) => deletedReplies == 0
          ? 'Comment deleted.'
          : 'Comment and ${_replies(deletedReplies)} deleted.',
      onSuccess: (_) => _patch((detail) => detail.copyWith(
            comments: detail.comments
                .where((item) =>
                    item.id != comment.id && !doomed.contains(item.id))
                .toList(growable: false),
          )),
    );
  }

  static String _replies(int count) =>
      '$count ${count == 1 ? 'reply' : 'replies'}';

  // --- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task'),
        actions: [RefreshIconButton(onPressed: _reload)],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final detail = _detail;
    if (detail == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return CenteredMessageCard(
        message: errorMessage(_loadError, fallback: 'Could not load this task.'),
        action: RetryButton(onPressed: _reload),
      );
    }

    final task = detail.task;
    final myId = _myId;
    final permissions = TaskPermissions.of(task, myId);
    final directory = widget.directory;
    return RefreshingColumn(
      refreshing: _loading,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TaskHeaderCard(
                task: task,
                permissions: permissions,
                assigneeLabel: directory.assigneesFull(task),
                createdByLabel: directory.fullLabel(task.createdById),
                projectName: widget.projectsById[task.projectId]?.name,
                onChangeStatus: () => _changeStatus(task),
                onEditTask: () => _editTask(task),
                onDeleteTask: () => _deleteTask(task),
                onRaiseBlocker: () => _raiseBlocker(task),
              ),
              const SizedBox(height: 20),
              SubtasksSection(
                subtasks: detail.subtasks,
                canAdd: permissions.canAddWork,
                onAdd: () => _addSubtask(task),
                onOpen: _openSubtask,
                assigneeLabel: directory.fullLabel,
              ),
              const SizedBox(height: 20),
              NotesSection(
                notes: detail.notes,
                canAdd: permissions.canAddWork,
                authorLabel: directory.fullLabel,
                currentUserId: myId,
                onEditNote: _editNote,
                onDeleteNote: _deleteNote,
                onAdd: (body) => _addNote(task, body),
              ),
              const SizedBox(height: 20),
              CommentsSection(
                comments: detail.comments,
                currentUserId: myId,
                authorLabel: directory.fullLabel,
                onEditComment: _editComment,
                onDeleteComment: _deleteComment,
                onPost: (body, {parentCommentId}) => _postComment(
                  task,
                  body,
                  parentCommentId: parentCommentId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
