import 'package:material_ui/material_ui.dart';

import '../task_models.dart';

/// A dropdown-shaped field that picks one project and offers a trailing
/// "+ New" button to create one inline. When no projects have loaded yet it
/// is disabled, with a hint that the server will default to "Unidentified".
class ProjectPickerField extends StatelessWidget {
  const ProjectPickerField({
    super.key,
    required this.projects,
    required this.selectedProjectId,
    required this.onChanged,
    required this.onCreateProject,
  });

  final List<Project> projects;
  final int? selectedProjectId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: selectedProjectId,
            decoration: InputDecoration(
              labelText: 'Project',
              helperText: projects.isEmpty
                  ? 'No projects loaded yet. Default will be "Unidentified".'
                  : null,
            ),
            // The "Unidentified" project sorts first on the server; keep
            // that order.
            items: [
              for (final project in projects)
                DropdownMenuItem<int>(
                  value: project.id,
                  child: _ProjectOption(project: project),
                ),
            ],
            onChanged: projects.isEmpty ? null : onChanged,
            validator: (value) {
              // The server defaults to "Unidentified" when no project_id is
              // sent, so an empty selection is only an error when projects
              // did load but none was picked.
              if (projects.isNotEmpty && value == null) {
                return 'Pick a project';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: onCreateProject,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New'),
          ),
        ),
      ],
    );
  }
}

class _ProjectOption extends StatelessWidget {
  const _ProjectOption({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(project.name)),
        if (project.isDefault) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'default',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
