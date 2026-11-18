import '../api/api_client.dart';
import '../auth/auth_api.dart' show AuthUser;
import 'task_models.dart';

/// Tasks, users and notifications. Every endpoint here is Bearer-protected;
/// callers pass the current access token (see [AuthController] for the
/// refresh-on-401 wrapper that supplies it).
class DataApi {
  DataApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Task> createTask({
    required String token,
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskType type = TaskType.decide,
    TaskDiscipline discipline = TaskDiscipline.decide,
    DateTime? startAt,
    DateTime? dueAt,
    int? assigneeId,
    int? parentTaskId,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'status': status.wire,
      'type': type.wire,
      'discipline': discipline.wire,
      if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (parentTaskId != null) 'parent_task_id': parentTaskId,
    };
    final json = await _client.post('/task/add', body, token: token);
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  /// Create a subtask under [parentTaskId] via `POST /task/subtask`. The server
  /// takes `created_by_id` from the token; the backend enforces that only the
  /// parent task's assignee may do this.
  Future<Task> createSubtask({
    required String token,
    required int parentTaskId,
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskType type = TaskType.decide,
    TaskDiscipline discipline = TaskDiscipline.decide,
    DateTime? startAt,
    DateTime? dueAt,
    int? assigneeId,
  }) async {
    final body = <String, dynamic>{
      'parent_task_id': parentTaskId,
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'status': status.wire,
      'type': type.wire,
      'discipline': discipline.wire,
      if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      if (assigneeId != null) 'assignee_id': assigneeId,
    };
    final json = await _client.post('/task/subtask', body, token: token);
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  /// Add a note to a task via `POST /task/note`. `author_id` comes from the
  /// token server-side.
  Future<TaskNote> addNote({
    required String token,
    required int taskId,
    required String body,
  }) async {
    final json = await _client.post(
      '/task/note',
      {'task_id': taskId, 'body': body},
      token: token,
    );
    return TaskNote.fromJson(json['note'] as Map<String, dynamic>);
  }

  /// Change a task's status via `POST /task/status`. Returns the updated task
  /// (with bumped `version`).
  Future<Task> changeStatus({
    required String token,
    required int taskId,
    required TaskStatus status,
  }) async {
    final json = await _client.post(
      '/task/status',
      {'task_id': taskId, 'status': status.wire},
      token: token,
    );
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  /// Fetch a task together with its direct subtasks and notes via
  /// `GET /task/detail?task_id=...`. Cache-busted so a note/status change made
  /// moments earlier is reflected on reload.
  Future<TaskDetail> taskDetail(String token, int taskId) async {
    final json = await _client.get(
      '/task/detail?task_id=$taskId',
      token: token,
      noCache: true,
    );
    return TaskDetail.fromJson(json);
  }

  Future<List<Task>> allTasks(String token) => _taskList('/task/all', token);

  Future<List<Task>> myTasks(String token) => _taskList('/task/mine', token);

  Future<List<Task>> completedTasks(String token) =>
      _taskList('/task/completed', token);

  Future<List<Task>> _taskList(String path, String token) async {
    final json = await _client.get(path, token: token, noCache: true);
    final items = json['tasks'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Task.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<AuthUser>> allUsers(String token) async {
    final json = await _client.get('/user/all', token: token, noCache: true);
    final items = json['users'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AuthUser.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<AppNotification>> notifications(String token) async {
    final json =
        await _client.get('/notification/all', token: token, noCache: true);
    final items = json['notifications'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
