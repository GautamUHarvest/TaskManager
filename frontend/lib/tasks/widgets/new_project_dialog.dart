import 'package:material_ui/material_ui.dart';

import '../../auth/auth_controller.dart';
import '../../common/submit_state.dart';
import '../../common/widgets/form_dialog.dart';

/// Creates a project. Pops the created [Project] on success, null on cancel.
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key, required this.controller});

  final AuthController controller;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await runSubmit(() async {
      final project = await widget.controller.createProject(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      if (mounted) Navigator.pop(context, project);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'New project',
      formKey: _formKey,
      width: 380,
      busy: submitting,
      error: submitError,
      submitLabel: 'Create',
      onSubmit: _submit,
      children: [
        TextFormField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          maxLength: 120,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Enter a project name';
            if (text.length > 120) {
              return 'Name must be 120 characters or fewer';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
          ),
        ),
      ],
    );
  }
}
