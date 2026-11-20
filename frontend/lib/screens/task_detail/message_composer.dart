import 'package:material_ui/material_ui.dart';

import '../../common/widgets/button_spinner.dart';

/// A multi-line text box with a send button, for posting notes and comments.
///
/// The field is emptied the instant the user hits send, the way a chat
/// composer should, rather than after the round-trip — the posted message
/// already appears optimistically. The text is put back only if [onSubmit]
/// reports failure, so nothing is lost on a 403 or a dropped connection.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.hintText,
    required this.buttonLabel,
    required this.onSubmit,
    this.labelText,
  });

  final String? labelText;
  final String hintText;
  final String buttonLabel;

  /// Posts the trimmed text; resolves to true on success.
  final Future<bool> Function(String body) onSubmit;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    _controller.clear();
    setState(() => _sending = true);
    final ok = await widget.onSubmit(body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) _controller.text = body;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 4000,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const ButtonSpinner(size: 16)
                : const Icon(Icons.send, size: 18),
            label: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}
