import 'package:material_ui/material_ui.dart';

import '../../common/widgets/muted_text.dart';
import '../../common/widgets/section_card.dart';
import '../../tasks/task_models.dart';
import 'authored_entry.dart';
import 'message_composer.dart';

/// The task's notes, oldest first, with a composer for assignees.
class NotesSection extends StatelessWidget {
  const NotesSection({
    super.key,
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
  final String Function(int? userId) authorLabel;

  /// Signed-in user; a note is editable/deletable only by its author.
  final int? currentUserId;
  final ValueChanged<TaskNote> onEditNote;
  final ValueChanged<TaskNote> onDeleteNote;

  /// Posts a note; resolves to true when it was created.
  final Future<bool> Function(String body) onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Notes (${notes.length})',
      children: [
        if (notes.isEmpty)
          const MutedText('No notes yet.')
        else
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AuthoredEntry(
                  authorLabel: authorLabel(note.authorId),
                  body: note.body,
                  createdAt: note.createdAt,
                  updatedAt: note.updatedAt,
                  isMine:
                      currentUserId != null && note.authorId == currentUserId,
                  onEdit: () => onEditNote(note),
                  onDelete: () => onDeleteNote(note),
                  actionsTooltip: 'Note actions',
                ),
              ),
            ),
        if (canAdd) ...[
          const Divider(height: 28),
          MessageComposer(
            labelText: 'Add a note',
            hintText: 'Share an update on this task…',
            buttonLabel: 'Post note',
            onSubmit: onAdd,
          ),
        ],
      ],
    );
  }
}
