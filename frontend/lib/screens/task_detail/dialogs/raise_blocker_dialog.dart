import 'package:material_ui/material_ui.dart';

import '../../../auth/auth_api.dart';
import '../../../auth/auth_controller.dart';
import '../../../common/submit_state.dart';
import '../../../common/widgets/form_dialog.dart';
import '../../../common/widgets/muted_text.dart';
import '../../../tasks/task_models.dart';

/// Raise a blocker: pick the member holding the task up and say why. On
/// submit the task is flagged `blocked` and that member gets an alert — a
/// modal popup straight away if they have a tab open, replayed on their next
/// connect if not. Pops the updated [Task] so the caller can repaint.
class RaiseBlockerDialog extends StatefulWidget {
  const RaiseBlockerDialog({
    super.key,
    required this.controller,
    required this.task,
    required this.candidates,
  });

  final AuthController controller;
  final Task task;

  /// Everyone who could be named — the signed-in user is already excluded.
  final List<AuthUser> candidates;

  @override
  State<RaiseBlockerDialog> createState() => _RaiseBlockerDialogState();
}

class _RaiseBlockerDialogState extends State<RaiseBlockerDialog>
    with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  int? _responsibleId;

  @override
  void initState() {
    super.initState();
    // Default to the only candidate when there is exactly one, so the common
    // two-person case is a single tap.
    if (widget.candidates.length == 1) {
      _responsibleId = widget.candidates.first.id;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final responsibleId = _responsibleId;
    if (responsibleId == null) {
      setState(() => submitError = 'Choose who is blocking this task.');
      return;
    }
    await runSubmit(() async {
      final updated = await widget.controller.raiseBlocker(
        taskId: widget.task.id,
        responsibleUserId: responsibleId,
        message: _messageController.text.trim(),
      );
      if (mounted) Navigator.pop(context, updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormDialog(
      title: 'Raise a blocker',
      icon: Icon(Icons.report_problem_outlined, color: theme.colorScheme.error),
      formKey: _formKey,
      busy: submitting,
      error: submitError,
      submitLabel: 'Raise blocker',
      destructive: true,
      onSubmit: _submit,
      children: [
        Text(
          widget.task.title,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _responsibleId,
          decoration: const InputDecoration(labelText: 'Who is blocking this?'),
          items: [
            for (final user in widget.candidates)
              DropdownMenuItem<int>(
                value: user.id,
                child: Text('${user.displayName} · ${user.employeeId}'),
              ),
          ],
          onChanged: (value) => setState(() => _responsibleId = value),
          validator: (value) => value == null ? 'Choose a member' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _messageController,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'What is blocked, and what do you need?',
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Describe the blocker';
            if (text.length > 4000) {
              return 'Message must be 4000 characters or fewer';
            }
            return null;
          },
        ),
        MutedText(
          'This sets the task to Blocked and alerts them right away.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
