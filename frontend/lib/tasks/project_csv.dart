import '../auth/auth_models.dart';
import '../common/date_format.dart';
import '../tasks/task_models.dart';
import '../tasks/user_directory.dart';

/// Column headings of the project export, in order. One row per task; the
/// project's own fields repeat on every row so each row stands alone when the
/// sheet is filtered or sorted.
const List<String> kProjectCsvColumns = [
  'Project ID',
  'Project Name',
  'Project Description',
  'Index',
  'Task ID',
  'Parent Task ID',
  'Title',
  'Description',
  'Status',
  'Type',
  'Discipline',
  'Start Date',
  'Due Date',
  'Assignees',
  'Created By',
  'Created At',
  'Updated At',
];

/// Builds the CSV export of [project] and its [tasks] (RFC 4180: CRLF line
/// endings, fields quoted when needed). People are written by name via
/// [directory]; enums use their display labels.
///
/// A project with no tasks still yields one row carrying the project's own
/// fields, so the file is never just a header.
///
/// The result starts with a UTF-8 byte-order mark so Excel opens non-ASCII
/// text (names, descriptions) correctly; other tools ignore it.
String buildProjectCsv({
  required Project project,
  required List<Task> tasks,
  required UserDirectory directory,
}) {
  final projectCells = [
    '${project.id}',
    project.name,
    project.description ?? '',
  ];

  final rows = <List<String>>[kProjectCsvColumns];
  if (tasks.isEmpty) {
    rows.add([
      ...projectCells,
      ...List.filled(kProjectCsvColumns.length - projectCells.length, ''),
    ]);
  }
  for (final task in tasks) {
    rows.add([
      ...projectCells,
      task.index?.toString() ?? '',
      '${task.id}',
      task.parentTaskId?.toString() ?? '',
      task.title,
      task.description ?? '',
      task.status.label,
      task.type.label,
      task.discipline.label,
      _date(task.startAt),
      _date(task.dueAt),
      task.allAssigneeIds.map((id) => _person(directory, id)).join('; '),
      task.createdById == null ? '' : _person(directory, task.createdById!),
      _dateTime(task.createdAt),
      _dateTime(task.updatedAt),
    ]);
  }

  final buffer = StringBuffer('﻿');
  for (final row in rows) {
    buffer
      ..write(row.map(_cell).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

/// A download filename for [project]'s export, e.g.
/// `project-rover-chassis-2026-11-23.csv`.
String projectCsvFilename(Project project, {DateTime? now}) {
  final slug = project.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final stem = slug.isEmpty ? 'project-${project.id}' : 'project-$slug';
  return '$stem-${formatDate(now ?? DateTime.now())}.csv';
}

/// A person's name only (no employee id), falling back to `User #id` when
/// the roster doesn't know them.
String _person(UserDirectory directory, int id) {
  final AuthUser? user = directory.usersById[id];
  return user == null ? 'User #$id' : UserDirectory.nameOf(user);
}

String _date(DateTime? value) => value == null ? '' : formatDate(value);

String _dateTime(DateTime? value) {
  if (value == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatDate(value)} ${two(value.hour)}:${two(value.minute)}';
}

/// Escapes one field. Text a spreadsheet would run as a formula (leading
/// `=`, `+`, `-`, `@`, tab or CR) is prefixed with `'` so a task title can't
/// execute when the file is opened in Excel.
String _cell(String value) {
  var text = value;
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) {
    text = "'$text";
  }
  final needsQuotes = text.contains(RegExp('[",\r\n]'));
  if (!needsQuotes) return text;
  return '"${text.replaceAll('"', '""')}"';
}
