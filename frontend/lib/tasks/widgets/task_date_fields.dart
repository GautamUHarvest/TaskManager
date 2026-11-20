import 'package:material_ui/material_ui.dart';

import '../../common/date_format.dart';

/// Optional start / due date pickers plus a "Clear dates" link.
///
/// Both dates are reported together through [onChanged] so clearing them is
/// a single update.
class TaskDateFields extends StatelessWidget {
  const TaskDateFields({
    super.key,
    required this.startDate,
    required this.dueDate,
    required this.onChanged,
    this.editingExisting = false,
    this.horizontal = false,
  });

  final DateTime? startDate;
  final DateTime? dueDate;
  final void Function(DateTime? start, DateTime? due) onChanged;

  /// A new task keeps due on or after start (or today). An existing task may
  /// already carry past dates, so both pickers then reach five years back
  /// (the picker throws if its initial date is out of range).
  final bool editingExisting;

  /// Puts the two buttons side by side instead of stacked.
  final bool horizontal;

  Future<void> _pickStart(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate ?? today,
      firstDate: DateTime(today.year - (editingExisting ? 5 : 1)),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) onChanged(picked, dueDate);
  }

  Future<void> _pickDue(BuildContext context) async {
    final today = DateTime.now();
    final firstDate = editingExisting
        ? DateTime(today.year - 5)
        : startDate ?? DateTime(today.year, today.month, today.day);
    var initialDate = dueDate ?? startDate ?? today;
    // A due date picked before the start was moved later would otherwise sit
    // before firstDate and make the picker throw.
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) onChanged(startDate, picked);
  }

  @override
  Widget build(BuildContext context) {
    final start = OutlinedButton.icon(
      onPressed: () => _pickStart(context),
      icon: const Icon(Icons.play_circle_outline),
      label: Text(
        startDate == null
            ? 'Start date (optional)'
            : 'Starts ${formatDate(startDate!)}',
      ),
    );
    final due = OutlinedButton.icon(
      onPressed: () => _pickDue(context),
      icon: const Icon(Icons.event_outlined),
      label: Text(
        dueDate == null ? 'Due date (optional)' : 'Due ${formatDate(dueDate!)}',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (horizontal)
          Row(
            children: [
              Expanded(child: start),
              const SizedBox(width: 12),
              Expanded(child: due),
            ],
          )
        else ...[
          start,
          const SizedBox(height: 8),
          due,
        ],
        if (startDate != null || dueDate != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(null, null),
              child: const Text('Clear dates'),
            ),
          ),
      ],
    );
  }
}
