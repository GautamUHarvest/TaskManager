import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';
import '../../common/widgets/muted_text.dart';
import '../../common/widgets/owner_actions_menu.dart';

/// Body of a note or comment: author + timestamp + owner menu on one line,
/// then the text, then an "Edited …" line when it was changed after posting.
/// The caller supplies the surrounding container and any [footer].
class AuthoredEntry extends StatelessWidget {
  const AuthoredEntry({
    super.key,
    required this.authorLabel,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
    required this.actionsTooltip,
    this.footer,
  });

  final String authorLabel;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Only the author may edit or delete.
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String actionsTooltip;
  final Widget? footer;

  bool get _wasEdited =>
      updatedAt != null && createdAt != null && updatedAt!.isAfter(createdAt!);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
            if (createdAt != null)
              MutedText(formatDate(createdAt!), style: theme.textTheme.bodySmall),
            OwnerActionsMenu(
              canEdit: isMine,
              canDelete: isMine,
              onEdit: onEdit,
              onDelete: onDelete,
              tooltip: actionsTooltip,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(body, style: theme.textTheme.bodyMedium),
        if (_wasEdited) ...[
          const SizedBox(height: 4),
          MutedText(
            'Edited ${formatDate(updatedAt!)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        if (footer != null) footer!,
      ],
    );
  }
}
