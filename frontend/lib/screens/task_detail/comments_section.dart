import 'package:material_ui/material_ui.dart';

import '../../common/widgets/button_spinner.dart';
import '../../common/widgets/muted_text.dart';
import '../../common/widgets/section_card.dart';
import '../../tasks/task_models.dart';
import 'authored_entry.dart';
import 'message_composer.dart';

/// Posts a comment (a reply when [parentCommentId] is set); resolves to true
/// on success.
typedef PostCommentCallback = Future<bool> Function(
  String body, {
  int? parentCommentId,
});

/// Threaded discussion. The server returns a flat list with
/// [TaskComment.parentCommentId]; this builds the tree and renders each
/// level with an indent plus a left guide line, so a reply to a reply sits
/// one level deeper than its parent. Anyone can comment; the task's
/// assignees and the parent-comment author are notified server-side.
class CommentsSection extends StatefulWidget {
  const CommentsSection({
    super.key,
    required this.comments,
    required this.currentUserId,
    required this.authorLabel,
    required this.onEditComment,
    required this.onDeleteComment,
    required this.onPost,
  });

  final List<TaskComment> comments;
  final int? currentUserId;
  final String Function(int? userId) authorLabel;

  /// A comment may be edited or deleted only by its author; deleting one
  /// also cascades its replies server-side.
  final ValueChanged<TaskComment> onEditComment;
  final ValueChanged<TaskComment> onDeleteComment;
  final PostCommentCallback onPost;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  /// The comment the inline reply composer is open under, if any. Only one
  /// reply composer is open at a time.
  int? _replyingTo;
  final _replyController = TextEditingController();
  bool _sendingReply = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _setReplyTarget(int? commentId) {
    setState(() {
      _replyingTo = commentId;
      _replyController.clear();
    });
  }

  Future<void> _sendReply() async {
    final target = _replyingTo;
    final body = _replyController.text.trim();
    if (target == null || body.isEmpty) return;
    // Close the composer and empty it immediately; the reply itself shows up
    // optimistically in the thread. On failure re-arm it with the original
    // text so the user can retry without retyping.
    _replyController.clear();
    setState(() {
      _sendingReply = true;
      _replyingTo = null;
    });
    final ok = await widget.onPost(body, parentCommentId: target);
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
    // Group by parent id so the tree can be built in one pass.
    final childrenByParent = <int?, List<TaskComment>>{};
    for (final comment in widget.comments) {
      childrenByParent.putIfAbsent(comment.parentCommentId, () => []).add(comment);
    }
    final topLevel = childrenByParent[null] ?? const <TaskComment>[];
    final thread = _CommentThread(
      childrenByParent: childrenByParent,
      authorLabel: widget.authorLabel,
      currentUserId: widget.currentUserId,
      onEditComment: widget.onEditComment,
      onDeleteComment: widget.onDeleteComment,
      replyingTo: _replyingTo,
      onReplyTargetChanged: _setReplyTarget,
      replyController: _replyController,
      sendingReply: _sendingReply,
      onSendReply: _sendReply,
    );
    return SectionCard(
      title: 'Comments (${widget.comments.length})',
      leadingIcon: Icons.forum_outlined,
      children: [
        if (topLevel.isEmpty)
          const MutedText('No comments yet. Start the discussion below.')
        else
          for (final comment in topLevel)
            _CommentNode(comment: comment, depth: 0, thread: thread),
        const Divider(height: 28),
        Text(
          'Add a comment',
          style:
              theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        MessageComposer(
          hintText: 'Write a comment… assignees will be notified.',
          buttonLabel: 'Post comment',
          onSubmit: (body) => widget.onPost(body),
        ),
      ],
    );
  }
}

/// Everything every node in the tree needs, bundled so the recursion only
/// passes the comment and its depth.
class _CommentThread {
  const _CommentThread({
    required this.childrenByParent,
    required this.authorLabel,
    required this.currentUserId,
    required this.onEditComment,
    required this.onDeleteComment,
    required this.replyingTo,
    required this.onReplyTargetChanged,
    required this.replyController,
    required this.sendingReply,
    required this.onSendReply,
  });

  final Map<int?, List<TaskComment>> childrenByParent;
  final String Function(int? userId) authorLabel;
  final int? currentUserId;
  final ValueChanged<TaskComment> onEditComment;
  final ValueChanged<TaskComment> onDeleteComment;
  final int? replyingTo;

  /// Opens the reply composer under a comment, or closes it with null.
  final ValueChanged<int?> onReplyTargetChanged;
  final TextEditingController replyController;
  final bool sendingReply;
  final VoidCallback onSendReply;
}

/// One comment plus its replies, rendered recursively one step deeper each
/// level.
class _CommentNode extends StatelessWidget {
  const _CommentNode({
    required this.comment,
    required this.depth,
    required this.thread,
  });

  /// Indent stops growing past this depth so long chains stay readable on
  /// narrow viewports; nesting still reads via the guide line.
  static const int _maxIndentDepth = 6;

  final TaskComment comment;
  final int depth;
  final _CommentThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replies =
        thread.childrenByParent[comment.id] ?? const <TaskComment>[];
    final isReplyTarget = thread.replyingTo == comment.id;
    final indentDepth = depth > _maxIndentDepth ? _maxIndentDepth : depth;
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * indentDepth, bottom: 10),
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
                    child: AuthoredEntry(
                      authorLabel: thread.authorLabel(comment.authorId),
                      body: comment.body,
                      createdAt: comment.createdAt,
                      updatedAt: comment.updatedAt,
                      isMine: thread.currentUserId != null &&
                          comment.authorId == thread.currentUserId,
                      onEdit: () => thread.onEditComment(comment),
                      onDelete: () => thread.onDeleteComment(comment),
                      actionsTooltip: 'Comment actions',
                      footer: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () => thread.onReplyTargetChanged(
                            isReplyTarget ? null : comment.id,
                          ),
                          icon: Icon(
                            isReplyTarget ? Icons.close : Icons.reply,
                            size: 16,
                          ),
                          label: Text(isReplyTarget ? 'Cancel' : 'Reply'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isReplyTarget)
            _ReplyComposer(
              controller: thread.replyController,
              hintText: 'Reply to ${thread.authorLabel(comment.authorId)}…',
              sending: thread.sendingReply,
              onSend: thread.onSendReply,
            ),
          for (final reply in replies)
            _CommentNode(comment: reply, depth: depth + 1, thread: thread),
        ],
      ),
    );
  }
}

/// Inline composer under the comment being replied to. Its controller lives
/// in the section so the text survives a failed post.
class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.hintText,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hintText;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // One extra indent step so the composer sits where the new reply will
      // land once posted.
      padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            maxLength: 4000,
            decoration: InputDecoration(hintText: hintText, isDense: true),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const ButtonSpinner(size: 14)
                  : const Icon(Icons.send, size: 16),
              label: const Text('Post reply'),
            ),
          ),
        ],
      ),
    );
  }
}
