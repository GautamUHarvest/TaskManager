import 'task_models.dart';

/// What the signed-in user may do with a task. These mirror the backend's
/// rules; hiding a control is a convenience, since the server answers 403
/// either way.
class TaskPermissions {
  const TaskPermissions._({required this.isAssignee, required this.isCreator});

  factory TaskPermissions.of(Task task, int? userId) {
    if (userId == null) {
      return const TaskPermissions._(isAssignee: false, isCreator: false);
    }
    return TaskPermissions._(
      isAssignee: task.allAssigneeIds.contains(userId),
      isCreator: task.createdById == userId,
    );
  }

  final bool isAssignee;
  final bool isCreator;

  /// Only an assignee may add subtasks and notes.
  bool get canAddWork => isAssignee;

  /// Creator or any assignee may edit, change status, and raise a blocker.
  bool get canEdit => isAssignee || isCreator;

  /// Any signed-in member may reassign any task to anyone. The server allows
  /// this only for an update that changes the assignees and nothing else.
  bool get canAssign => true;

  /// Only the creator may delete.
  bool get canDelete => isCreator;
}
