import 'package:material_ui/material_ui.dart';

import '../../auth/auth_api.dart';
import '../../common/widgets/initial_avatar.dart';
import '../user_directory.dart';

/// Multi-select assignee field. Shows a chip for each picked user and a menu
/// of remaining users behind an "Add teammate" button. An empty picker means
/// the task is unassigned (the server still accepts it).
class AssigneePickerField extends StatelessWidget {
  const AssigneePickerField({
    super.key,
    required this.users,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<AuthUser> users;
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userById = {for (final user in users) user.id: user};
    final remaining =
        users.where((user) => !selectedIds.contains(user.id)).toList();
    final canAdd = remaining.isNotEmpty;

    // When the roster hasn't arrived yet (initial load, network blip) say so
    // instead of pretending nobody is addable.
    final addLabel = users.isEmpty
        ? 'Loading teammates…'
        : canAdd
            ? 'Add teammate'
            : 'Everyone added';

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
                        : UserDirectory.nameOf(userById[id]!),
                  ),
                  onDeleted: () => onChanged([...selectedIds]..remove(id)),
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
            enabled: canAdd,
            onSelected: (id) {
              if (!selectedIds.contains(id)) onChanged([...selectedIds, id]);
            },
            tooltip: addLabel,
            itemBuilder: (context) => [
              for (final user in remaining)
                PopupMenuItem<int>(
                  value: user.id,
                  child: _UserOption(user: user),
                ),
            ],
            child: _AddTeammateButton(label: addLabel, enabled: canAdd),
          ),
        ),
      ],
    );
  }
}

class _UserOption extends StatelessWidget {
  const _UserOption({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = UserDirectory.nameOf(user);
    return Row(
      children: [
        InitialAvatar(
          name: name,
          radius: 12,
          textStyle: theme.textTheme.labelSmall,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            user.employeeId.isEmpty ? name : '$name · ${user.employeeId}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AddTeammateButton extends StatelessWidget {
  const _AddTeammateButton({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = enabled ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? scheme.outline : scheme.outlineVariant,
        ),
        color: enabled
            ? null
            : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_1, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
