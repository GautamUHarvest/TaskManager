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
  });

  final AuthController controller;
  final int taskId;
  final Map<int, AuthUser> usersById;
  final Map<int, Project> projectsById;

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
      await widget.controller.changeTaskStatus(
        taskId: task.id,
        status: picked,
      );
      if (!mounted) return;
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

  void _showError(Object error) {
    final message =
        error is AuthApiException ? error.message : 'Something went wrong.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSubtask(Task subtask) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TaskDetailScreen(
              controller: widget.controller,
              taskId: subtask.id,
              usersById: widget.usersById,
              projectsById: widget.projectsById,
            ),
          ),
        )
        // Returning may have changed this task's children/status.
        .then((_) => _reload());
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
                          onCommentPosted: _reload,
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.task,
    required this.assigneeLabel,
    required this.createdByLabel,
    required this.projectName,
    required this.canChangeStatus,
    required this.onChangeStatus,
  });

  final Task task;
  final String assigneeLabel;
  final String createdByLabel;
  final String? projectName;
  final bool canChangeStatus;
  final VoidCallback onChangeStatus;

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
              task.title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
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
    required this.onAdd,
  });

  final List<TaskNote> notes;
  final bool canAdd;
  final String Function(int?) authorLabel;

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
    setState(() => _sending = true);
    final ok = await widget.onAdd(body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _controller.clear();
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
  const _NoteTile({required this.note, required this.authorLabel});

  final TaskNote note;
  final String authorLabel;

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
            ],
          ),
          const SizedBox(height: 6),
          Text(note.body, style: theme.textTheme.bodyMedium),
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
    required this.onCommentPosted,
  });

  final List<TaskComment> comments;
  final int taskId;
  final AuthController controller;
  final int? currentUserId;
  final String Function(int?) authorLabel;
  final VoidCallback onCommentPosted;

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
      await widget.controller.addComment(
        taskId: widget.taskId,
        body: body,
        parentCommentId: parentCommentId,
      );
      widget.onCommentPosted();
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
    setState(() => _sendingTopLevel = true);
    final ok = await _post(body: body);
    if (!mounted) return;
    setState(() => _sendingTopLevel = false);
    if (ok) _topLevelController.clear();
  }

  Future<void> _sendReply() async {
    final target = _replyingTo;
    final body = _replyController.text.trim();
    if (target == null || body.isEmpty) return;
    setState(() => _sendingReply = true);
    final ok = await _post(body: body, parentCommentId: target);
    if (!mounted) return;
    setState(() {
      _sendingReply = false;
      if (ok) {
        _replyController.clear();
        _replyingTo = null;
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
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(comment.body,
                            style: theme.textTheme.bodyMedium),
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
