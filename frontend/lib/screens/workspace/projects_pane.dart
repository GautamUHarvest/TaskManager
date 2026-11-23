import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';
import '../../common/widgets/future_view.dart';
import '../../common/widgets/message_card.dart';
import '../../common/widgets/muted_text.dart';
import '../../common/widgets/pane_scaffold.dart';
import '../../tasks/task_models.dart';
import '../../tasks/user_directory.dart';
import '../../tasks/widgets/task_chips.dart';

/// Every project with its description. Tapping one opens its task list.
class ProjectsPane extends StatefulWidget {
  const ProjectsPane({
    super.key,
    required this.loader,
    required this.directory,
    required this.onOpenProject,
  });

  final Future<List<Project>> Function() loader;
  final UserDirectory directory;
  final ValueChanged<Project> onOpenProject;

  @override
  State<ProjectsPane> createState() => _ProjectsPaneState();
}

class _ProjectsPaneState extends State<ProjectsPane> {
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() => setState(() => _future = widget.loader());

  @override
  Widget build(BuildContext context) {
    return PaneScaffold(
      title: 'Projects',
      trailing: RefreshIconButton(onPressed: _reload),
      child: FutureView<List<Project>>(
        future: _future,
        onRetry: _reload,
        builder: (context, projects) {
          if (projects.isEmpty) {
            return const MessageListView(message: 'No projects yet.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MutedText(
                projects.length == 1
                    ? '1 project'
                    : '${projects.length} projects',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    return _ProjectCard(
                      project: project,
                      createdByLabel: project.createdById == null
                          ? 'System'
                          : widget.directory.fullLabel(
                              project.createdById,
                              ifNull: 'Unknown',
                            ),
                      onTap: () => widget.onOpenProject(project),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.createdByLabel,
    required this.onTap,
  });

  final Project project;
  final String createdByLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = project.description?.trim() ?? '';
    final createdAt = project.createdAt;
    final metaStyle = theme.textTheme.bodySmall;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.folder_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          project.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (project.isDefault) const TagChip(label: 'Default'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    description.isEmpty
                        ? const MutedText('No description')
                        : Text(description),
                    const SizedBox(height: 10),
                    MutedText(
                      createdAt == null
                          ? 'By $createdByLabel'
                          : 'By $createdByLabel · ${formatDate(createdAt)}',
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
