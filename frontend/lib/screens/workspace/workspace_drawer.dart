import 'package:material_ui/material_ui.dart';

import 'brand_mark.dart';
import 'workspace_section.dart';

/// Primary navigation entries, in drawer order.
const List<({WorkspaceSection section, IconData icon, String label})>
    _navItems = [
  (
    section: WorkspaceSection.home,
    icon: Icons.space_dashboard_outlined,
    label: 'Dashboard',
  ),
  (
    section: WorkspaceSection.assignedToMe,
    icon: Icons.assignment_ind_outlined,
    label: 'My Tasks',
  ),
  (
    section: WorkspaceSection.allTasks,
    icon: Icons.list_alt_outlined,
    label: 'All Tasks',
  ),
  (
    section: WorkspaceSection.completedTasks,
    icon: Icons.check_circle_outline,
    label: 'Completed',
  ),
  (
    section: WorkspaceSection.projects,
    icon: Icons.folder_outlined,
    label: 'Projects',
  ),
  (
    section: WorkspaceSection.allUsers,
    icon: Icons.groups_outlined,
    label: 'Team',
  ),
];

/// The workspace navigation drawer: brand header, "New Task" button, the
/// section list, and a profile entry pinned at the bottom.
class WorkspaceDrawer extends StatelessWidget {
  const WorkspaceDrawer({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final WorkspaceSection selected;

  /// Called with the tapped section. The caller is responsible for closing
  /// the drawer.
  final ValueChanged<WorkspaceSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  const BrandMark(),
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
                onPressed: () => onSelect(WorkspaceSection.createTask),
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
                  for (final item in _navItems)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: ListTile(
                        selected: selected == item.section,
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        shape: itemShape,
                        onTap: () => onSelect(item.section),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                selected: selected == WorkspaceSection.profile,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.person_outline, size: 18),
                ),
                title: const Text('Profile'),
                subtitle: const Text('Account & sign out'),
                shape: itemShape,
                onTap: () => onSelect(WorkspaceSection.profile),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
