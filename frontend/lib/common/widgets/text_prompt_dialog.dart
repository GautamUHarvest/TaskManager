import 'package:material_ui/material_ui.dart';

/// Small single-field multi-line editor (used for note and comment bodies).
/// Resolves to the trimmed text, or null when cancelled or saved unchanged —
/// so callers can skip the round-trip and the version bump.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result == initialValue.trim()) return null;
    return result;
  } finally {
    controller.dispose();
  }
}
