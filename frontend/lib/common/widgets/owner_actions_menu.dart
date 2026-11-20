import 'package:material_ui/material_ui.dart';

enum _OwnerAction { edit, delete }

/// Edit/delete overflow menu for a record the signed-in user owns (a task,
/// note or comment). Renders nothing when they may do neither.
class OwnerActionsMenu extends StatelessWidget {
  const OwnerActionsMenu({
    super.key,
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

  /// Smaller icon and menu, for use inside list tiles.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<_OwnerAction>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: dense ? 18 : 24),
      constraints: dense ? const BoxConstraints(minWidth: 140) : null,
      onSelected: (action) => switch (action) {
        _OwnerAction.edit => onEdit(),
        _OwnerAction.delete => onDelete(),
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(
            value: _OwnerAction.edit,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined, size: 20),
              title: Text('Edit'),
            ),
          ),
        if (canDelete)
          PopupMenuItem(
            value: _OwnerAction.delete,
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
