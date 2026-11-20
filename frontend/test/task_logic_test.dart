import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_frontend/auth/auth_models.dart';
import 'package:task_manager_frontend/auth/auth_validators.dart';
import 'package:task_manager_frontend/tasks/task_models.dart';
import 'package:task_manager_frontend/tasks/task_permissions.dart';
import 'package:task_manager_frontend/tasks/user_directory.dart';

Task _task({
  int id = 1,
  int? assigneeId,
  List<int> assigneeIds = const [],
  int? createdById,
}) =>
    Task(
      id: id,
      title: 'Task $id',
      status: TaskStatus.todo,
      assigneeId: assigneeId,
      assigneeIds: assigneeIds,
      createdById: createdById,
    );

TaskComment _comment(int id, {int? parent}) =>
    TaskComment(id: id, taskId: 1, parentCommentId: parent, body: 'c$id');

const _alice = AuthUser(
  id: 1,
  employeeId: 'EMP1',
  email: 'alice@uharvest.in',
  displayName: 'Alice Smith',
);
const _bob = AuthUser(
  id: 2,
  employeeId: 'EMP2',
  email: 'bob@uharvest.in',
  displayName: 'Bob Jones',
);

void main() {
  group('Task.allAssigneeIds', () {
    test('prefers the list', () {
      expect(_task(assigneeId: 9, assigneeIds: [1, 2]).allAssigneeIds, [1, 2]);
    });
    test('falls back to the single id', () {
      expect(_task(assigneeId: 9).allAssigneeIds, [9]);
    });
    test('is empty when unassigned', () {
      expect(_task().allAssigneeIds, isEmpty);
    });
  });

  group('TaskDetail', () {
    final detail = TaskDetail(
      task: _task(),
      subtasks: const [],
      notes: const [],
      comments: [
        _comment(1),
        _comment(2, parent: 1),
        _comment(3, parent: 2),
        _comment(4, parent: 1),
        _comment(5),
        _comment(6, parent: 5),
      ],
    );

    test('replyIdsUnder collects the whole subtree', () {
      expect(detail.replyIdsUnder(1), {2, 3, 4});
      expect(detail.replyIdsUnder(2), {3});
      expect(detail.replyIdsUnder(3), isEmpty);
    });

    test('copyWith replaces only the given fields', () {
      final updated = detail.copyWith(notes: const []);
      expect(updated.task, same(detail.task));
      expect(updated.comments, same(detail.comments));
    });
  });

  group('TaskPermissions', () {
    final task = _task(assigneeIds: [1], createdById: 2);

    test('assignee may add work and edit, not delete', () {
      final access = TaskPermissions.of(task, 1);
      expect(access.canAddWork, isTrue);
      expect(access.canEdit, isTrue);
      expect(access.canDelete, isFalse);
    });

    test('creator may edit and delete, not add work', () {
      final access = TaskPermissions.of(task, 2);
      expect(access.canAddWork, isFalse);
      expect(access.canEdit, isTrue);
      expect(access.canDelete, isTrue);
    });

    test('outsider and signed-out user get nothing', () {
      for (final userId in [3, null]) {
        final access = TaskPermissions.of(task, userId);
        expect(access.canAddWork || access.canEdit || access.canDelete,
            isFalse);
      }
    });
  });

  group('UserDirectory', () {
    const directory =
        UserDirectory({1: _alice, 2: _bob}, currentUserId: 1);

    test('shortLabel', () {
      expect(directory.shortLabel(null), 'Unassigned');
      expect(directory.shortLabel(1), 'You');
      expect(directory.shortLabel(2), 'Bob Jones');
      expect(directory.shortLabel(7), 'User #7');
    });

    test('fullLabel', () {
      expect(directory.fullLabel(2), 'Bob Jones · EMP2');
      expect(directory.fullLabel(null), 'Unassigned');
      expect(directory.fullLabel(null, ifNull: 'Unknown'), 'Unknown');
      expect(directory.fullLabel(7), 'User #7');
    });

    test('assigneesSummary', () {
      expect(directory.assigneesSummary(_task()), 'Unassigned');
      expect(directory.assigneesSummary(_task(assigneeIds: [2])), 'Bob Jones');
      expect(directory.assigneesSummary(_task(assigneeIds: [1, 2])),
          'You & Bob Jones');
      expect(directory.assigneesSummary(_task(assigneeIds: [2, 1, 7])),
          'Bob Jones +2 others');
    });

    test('nameOf falls back through the blank fields', () {
      const blank =
          AuthUser(id: 5, employeeId: '', email: '', displayName: '  ');
      expect(UserDirectory.nameOf(blank), 'User #5');
      expect(UserDirectory.nameOf(_alice), 'Alice Smith');
    });
  });

  group('auth validators', () {
    test('company email', () {
      expect(isValidCompanyEmail('a.b@uharvest.in'), isTrue);
      expect(isValidCompanyEmail('A@UHARVEST.IN'), isTrue);
      expect(isValidCompanyEmail('a@gmail.com'), isFalse);
    });

    test('employee id', () {
      expect(isValidEmployeeId('EMP_1.a-b'), isTrue);
      expect(isValidEmployeeId('has space'), isFalse);
      expect(isValidEmployeeId('x' * 65), isFalse);
    });

    test('password', () {
      expect(isValidPassword('Abc1!x'), isTrue);
      expect(isValidPassword('abc1!x'), isFalse); // no uppercase
      expect(isValidPassword('Abcde!'), isFalse); // no digit
      expect(isValidPassword('Abc123'), isFalse); // no symbol
      expect(isValidPassword('Ab1!'), isFalse); // too short
    });
  });
}
