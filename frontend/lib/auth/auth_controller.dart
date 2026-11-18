import 'package:flutter/foundation.dart';

import '../tasks/data_api.dart';
import '../tasks/task_models.dart';
import 'auth_api.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.api, {DataApi? data}) : data = data ?? DataApi();

  final AuthApi api;
  final DataApi data;

  AuthTokens? _tokens;
  DateTime? _accessExpiresAt;

  bool get isAuthenticated => _tokens != null;

  /// The signed-in user (from the login/refresh payload), or null when signed
  /// out. Used to label "assigned to you" and to default the assignee picker.
  AuthUser? get currentUser => _tokens?.user;

  Future<void> register({
    required String employeeId,
    required String email,
    required String displayName,
    required String password,
  }) =>
      api.register(
        employeeId: employeeId,
        email: email,
        displayName: displayName,
        password: password,
      );

  Future<void> login(String login, String password) async {
    _setTokens(await api.login(login, password));
  }

  Future<AuthUser> loadProfile() => _authorized(api.profile);

  Future<void> logout() async {
    await _refreshIfExpiring();
    await api.logout(_requireTokens().accessToken);
    _clearTokens();
  }

  // --- Data (all Bearer-protected, routed through [_authorized]) ------------

  Future<List<Task>> myTasks() => _authorized(data.myTasks);

  Future<List<Task>> allTasks() => _authorized(data.allTasks);

  Future<List<Task>> completedTasks() => _authorized(data.completedTasks);

  Future<List<AuthUser>> allUsers() => _authorized(data.allUsers);

  Future<List<AppNotification>> notifications() =>
      _authorized(data.notifications);

  Future<Task> createTask({
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskType type = TaskType.decide,
    TaskDiscipline discipline = TaskDiscipline.decide,
    DateTime? startAt,
    DateTime? dueAt,
    int? assigneeId,
    int? parentTaskId,
  }) =>
      _authorized((token) => data.createTask(
            token: token,
            title: title,
            description: description,
            status: status,
            type: type,
            discipline: discipline,
            startAt: startAt,
            dueAt: dueAt,
            assigneeId: assigneeId,
            parentTaskId: parentTaskId,
          ));

  Future<TaskDetail> taskDetail(int taskId) =>
      _authorized((token) => data.taskDetail(token, taskId));

  Future<Task> createSubtask({
    required int parentTaskId,
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskType type = TaskType.decide,
    TaskDiscipline discipline = TaskDiscipline.decide,
    DateTime? startAt,
    DateTime? dueAt,
    int? assigneeId,
  }) =>
      _authorized((token) => data.createSubtask(
            token: token,
            parentTaskId: parentTaskId,
            title: title,
            description: description,
            status: status,
            type: type,
            discipline: discipline,
            startAt: startAt,
            dueAt: dueAt,
            assigneeId: assigneeId,
          ));

  Future<TaskNote> addNote({required int taskId, required String body}) =>
      _authorized(
        (token) => data.addNote(token: token, taskId: taskId, body: body),
      );

  Future<Task> changeTaskStatus({
    required int taskId,
    required TaskStatus status,
  }) =>
      _authorized(
        (token) => data.changeStatus(token: token, taskId: taskId, status: status),
      );

  /// Runs [action] with a fresh access token, refreshing proactively before
  /// expiry and once more if the server still answers 401.
  Future<T> _authorized<T>(Future<T> Function(String token) action) async {
    await _refreshIfExpiring();
    try {
      return await action(_requireTokens().accessToken);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      await _refresh();
      return action(_requireTokens().accessToken);
    }
  }

  Future<void> _refreshIfExpiring() async {
    if (_accessExpiresAt == null ||
        _accessExpiresAt!.isBefore(
          DateTime.now().add(const Duration(seconds: 30)),
        )) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final current = _requireTokens();
    _setTokens(await api.refresh(current.refreshToken));
  }

  AuthTokens _requireTokens() {
    final tokens = _tokens;
    if (tokens == null) {
      throw const AuthApiException('Your session has ended. Please sign in.');
    }
    return tokens;
  }

  void _setTokens(AuthTokens tokens) {
    _tokens = tokens;
    _accessExpiresAt = DateTime.now().add(Duration(seconds: tokens.expiresIn));
    notifyListeners();
  }

  void _clearTokens() {
    _tokens = null;
    _accessExpiresAt = null;
    notifyListeners();
  }
}
