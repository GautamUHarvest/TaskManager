import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_frontend/auth/auth_models.dart';
import 'package:task_manager_frontend/tasks/project_csv.dart';
import 'package:task_manager_frontend/tasks/task_models.dart';
import 'package:task_manager_frontend/tasks/user_directory.dart';

const _alice = AuthUser(
  id: 1,
  employeeId: 'EMP1',
  email: 'alice@uharvest.in',
  displayName: 'Alice Smith',
);

const _directory = UserDirectory({1: _alice});

const _project = Project(id: 7, name: 'Rover, Mk II', description: 'Field bot');

/// Data lines of [csv] (BOM and trailing CRLF stripped).
List<String> _lines(String csv) {
  expect(csv.startsWith('﻿'), isTrue);
  expect(csv.endsWith('\r\n'), isTrue);
  return csv.substring(1, csv.length - 2).split('\r\n');
}

void main() {
  test('one row per task with every field, quoted when needed', () {
    final csv = buildProjectCsv(
      project: _project,
      directory: _directory,
      tasks: [
        Task(
          id: 3,
          parentTaskId: 2,
          title: 'Say "hi"',
          description: 'line one\nline two',
          status: TaskStatus.inProgress,
          type: TaskType.code,
          discipline: TaskDiscipline.software,
          startAt: DateTime(2026, 1, 5),
          dueAt: DateTime(2026, 2, 1),
          assigneeIds: const [1, 9],
          createdById: 1,
          createdAt: DateTime(2026, 1, 4, 9, 30),
          updatedAt: DateTime(2026, 1, 6, 14, 5),
        ),
      ],
    );
    final lines = _lines(csv);
    expect(lines.first, kProjectCsvColumns.join(','));
    expect(
      csv,
      contains(
        '7,"Rover, Mk II",Field bot,3,2,"Say ""hi""","line one\nline two",'
        'In progress,Code,Software,2026-01-05,2026-02-01,'
        'Alice Smith (EMP1); User #9,Alice Smith (EMP1),'
        '2026-01-04 09:30,2026-01-06 14:05\r\n',
      ),
    );
  });

  test('an empty project still yields its own row', () {
    final lines = _lines(
      buildProjectCsv(
          project: _project, tasks: const [], directory: _directory),
    );
    expect(lines, hasLength(2));
    expect(lines[1].split(',').length, kProjectCsvColumns.length + 1);
    expect(lines[1], startsWith('7,"Rover, Mk II",Field bot,'));
  });

  test('formula-like text is neutralised', () {
    final csv = buildProjectCsv(
      project: const Project(id: 1, name: '=cmd'),
      directory: _directory,
      tasks: const [
        Task(id: 1, title: '+SUM(A1)', status: TaskStatus.todo),
      ],
    );
    expect(csv, contains("1,'=cmd,,1,,'+SUM(A1),"));
  });

  test('filename is a slug of the project name and the date', () {
    expect(
      projectCsvFilename(_project, now: DateTime(2026, 11, 23)),
      'project-rover-mk-ii-2026-11-23.csv',
    );
    expect(
      projectCsvFilename(const Project(id: 4, name: '***'),
          now: DateTime(2026, 11, 23)),
      'project-4-2026-11-23.csv',
    );
  });
}
