import 'dart:async';

import 'package:flutter/foundation.dart';

import '../realtime/blocker_socket.dart';
import '../tasks/data_api.dart';
import '../tasks/task_models.dart';
import 'auth_api.dart';
import 'token_storage.dart';

class AuthController extends ChangeNotifier {
  AuthController(
    this.api, {
    DataApi? data,
    TokenStorage? storage,
  })  : data = data ?? DataApi(),
        _storage = storage ?? TokenStorage();

  final AuthApi api;
  final DataApi data;
  final TokenStorage _storage;

  AuthTokens? _tokens;
  DateTime? _accessExpiresAt;
  bool _restoring = false;

  /// Ids the current session has already shown the user. Kept in memory so
  /// once a notification has been seen it stops reappearing in the bell /
  /// dialog on subsequent refreshes within this session (reload clears it,
  /// matching the rest of this app's in-memory-only session model).
  final Set<int> _readNotificationIds = <int>{};

  // --- Real-time blocker alerts ---------------------------------------------
  // One stream carries both delivery paths — the live WebSocket push and the
  // replay of anything raised while the user was offline — so the UI has a
  // single thing to listen to and cannot tell (or care) which it was.

  BlockerSocket? _blockerSocket;
  final StreamController<BlockerAlert> _blockerAlerts =
      StreamController<BlockerAlert>.broadcast();

  /// How often to poll for blockers while the WebSocket is not live. Short
  /// enough to still feel immediate, and trivial load for a 25-account cap.
  static const Duration _blockerPollInterval = Duration(seconds: 10);
  Timer? _blockerPoll;

  /// Alert ids already handed to the UI this session, so a replayed alert
  /// that also arrives live is only shown once.
  final Set<int> _deliveredBlockerIds = <int>{};

  /// Blocker alerts for the signed-in user. The UI shows each as a modal that
  /// stays up until acknowledged via [acknowledgeBlocker].
  Stream<BlockerAlert> get blockerAlerts => _blockerAlerts.stream;

  bool get isAuthenticated => _tokens != null;

  /// True while the controller is swapping a persisted refresh token for a
  /// live access token on app boot. The UI shows a brief splash rather than
  /// the signed-out screen so a reload doesn't flash the login page.
  bool get isRestoring => _restoring;

  /// The signed-in user (from the login/refresh payload), or null when signed
  /// out. Used to label "assigned to you" and to default the assignee picker.
  AuthUser? get currentUser => _tokens?.user;

  /// Tries to resurrect a prior session on app boot. The refresh token is read
  /// from localStorage and exchanged for a new access token; the server rotates
  /// it and we persist the fresh one. If the stored token is dead the server
  /// answers 401 and we fall through to the sign-in screen. The cached user
  /// lets the shell paint immediately instead of flashing the login page during
  /// the refresh round-trip.
  Future<void> restore() async {
    final cached = _storage.read();
    if (cached == null) return;
    _restoring = true;
    notifyListeners();
    try {
      _setTokens(await api.refresh(cached.refreshToken));
    } on AuthApiException {
      _storage.clear();
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

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

  // --- Blockers -------------------------------------------------------------

  /// Flags [taskId] as blocked on [responsibleUserId] and alerts them. The
  /// server pushes it to their open tabs immediately and stores it so they
  /// still see it if they are offline.
  Future<Task> raiseBlocker({
    required int taskId,
    required int responsibleUserId,
    required String message,
  }) =>
      _authorized((token) => data.raiseBlocker(
            token: token,
            taskId: taskId,
            responsibleUserId: responsibleUserId,
            message: message,
          ));

  /// Dismisses an alert so the server stops replaying it on reconnect.
  Future<void> acknowledgeBlocker(int notificationId) => _authorized(
        (token) => data.acknowledgeNotification(
          token: token,
          notificationId: notificationId,
        ),
      );

  /// Opens the live channel and replays anything missed while offline. Safe
  /// to call more than once — a socket is only created if there isn't one.
  void _startBlockerChannel() {
    if (_blockerSocket != null || _tokens == null) return;
    final socket = BlockerSocket(
      // Resolved per connect rather than captured, because the access token is
      // short-lived and rotates; this routes through the same refresh logic
      // every other call uses.
      tokenProvider: () async {
        await _refreshIfExpiring();
        return _requireTokens().accessToken;
      },
    );
    _blockerSocket = socket;
    socket.alerts.listen(_emitBlocker);
    socket.connect();
    unawaited(_replayPendingBlockers());

    // Fallback poll. The WebSocket is the fast path, but it only works if the
    // deployment actually proxies WebSocket upgrades (nginx needs an explicit
    // /ws/ location) — and it can drop for ordinary network reasons. Polling
    // whenever the socket is not live means a blocker still surfaces within
    // seconds instead of waiting for the next page load, which is the whole
    // point of the feature. It stands down the moment the socket is ready, so
    // a healthy deployment pays nothing for it.
    _blockerPoll?.cancel();
    _blockerPoll = Timer.periodic(_blockerPollInterval, (_) {
      if (_tokens == null) return;
      if (_blockerSocket?.isReady ?? false) return;
      unawaited(_replayPendingBlockers());
    });
  }

  /// Pulls blockers raised while this user had no tab open and feeds them
  /// through the same stream as live pushes. Failure is non-fatal: they are
  /// still in the notification list, and the next reconnect tries again.
  Future<void> _replayPendingBlockers() async {
    try {
      for (final alert in await _authorized(data.pendingBlockers)) {
        _emitBlocker(alert);
      }
    } catch (_) {
      // Signed out mid-flight, endpoint unavailable, or the network dropped.
      // Catch-all on purpose: this runs unawaited, so anything escaping here
      // would surface as an unhandled zone error and take the app down. The
      // alerts are still stored server-side and replay on the next connect.
    }
  }

  void _emitBlocker(BlockerAlert alert) {
    if (_blockerAlerts.isClosed) return;
    // A replayed alert can race the live push of the same row; show it once.
    if (!_deliveredBlockerIds.add(alert.id)) return;
    _blockerAlerts.add(alert);
  }

  void _stopBlockerChannel() {
    _blockerPoll?.cancel();
    _blockerPoll = null;
    _blockerSocket?.dispose();
    _blockerSocket = null;
    _deliveredBlockerIds.clear();
  }

  @override
  void dispose() {
    _stopBlockerChannel();
    _blockerAlerts.close();
    super.dispose();
  }

  // --- Data (all Bearer-protected, routed through [_authorized]) ------------

  Future<List<Task>> myTasks() => _authorized(data.myTasks);

  Future<List<Task>> allTasks() => _authorized(data.allTasks);

  Future<List<Task>> completedTasks() => _authorized(data.completedTasks);

  Future<List<AuthUser>> allUsers() => _authorized(data.allUsers);

  /// Notifications the user has not yet dismissed. Server-returned items
  /// whose ids are in [_readNotificationIds] (dismissed earlier this session)
  /// are filtered out so a read notification doesn't keep reappearing.
  Future<List<AppNotification>> notifications() async {
    final items = await _authorized(data.notifications);
    return items
        .where((item) => !_readNotificationIds.contains(item.id))
        .toList(growable: false);
  }

  /// Mark [ids] as read for this session. Called by the notifications dialog
  /// when the user opens it (the act of opening the panel counts as seeing
  /// the items it shows). Notifies listeners so the bell badge updates.
  void markNotificationsRead(Iterable<int> ids) {
    final before = _readNotificationIds.length;
    _readNotificationIds.addAll(ids);
    if (_readNotificationIds.length != before) {
      notifyListeners();
    }
  }

  Future<Task> createTask({
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskType type = TaskType.decide,
    TaskDiscipline discipline = TaskDiscipline.decide,
    DateTime? startAt,
    DateTime? dueAt,
    List<int> assigneeIds = const [],
    int? parentTaskId,
    int? projectId,
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
            assigneeIds: assigneeIds,
            parentTaskId: parentTaskId,
            projectId: projectId,
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
    List<int> assigneeIds = const [],
    int? projectId,
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
            assigneeIds: assigneeIds,
            projectId: projectId,
          ));

  Future<TaskComment> addComment({
    required int taskId,
    required String body,
    int? parentCommentId,
  }) =>
      _authorized(
        (token) => data.addComment(
          token: token,
          taskId: taskId,
          body: body,
          parentCommentId: parentCommentId,
        ),
      );

  Future<List<Project>> allProjects() => _authorized(data.allProjects);

  Future<Project> createProject({
    required String name,
    String? description,
  }) =>
      _authorized(
        (token) => data.createProject(
          token: token,
          name: name,
          description: description,
        ),
      );

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

  // --- Edit / delete --------------------------------------------------------
  // The server owns the permission rules (task: creator or assignee may edit,
  // creator only may delete; note/comment: author only) and answers 403 when
  // they are not met. The UI hides the controls as a convenience, but never
  // relies on that for enforcement.

  Future<Task> updateTask({
    required int taskId,
    String? title,
    String? description,
    bool clearDescription = false,
    TaskStatus? status,
    TaskType? type,
    TaskDiscipline? discipline,
    DateTime? startAt,
    bool clearStartAt = false,
    DateTime? dueAt,
    bool clearDueAt = false,
    List<int>? assigneeIds,
    int? projectId,
  }) =>
      _authorized((token) => data.updateTask(
            token: token,
            taskId: taskId,
            title: title,
            description: description,
            clearDescription: clearDescription,
            status: status,
            type: type,
            discipline: discipline,
            startAt: startAt,
            clearStartAt: clearStartAt,
            dueAt: dueAt,
            clearDueAt: clearDueAt,
            assigneeIds: assigneeIds,
            projectId: projectId,
          ));

  Future<void> deleteTask(int taskId) =>
      _authorized((token) => data.deleteTask(token: token, taskId: taskId));

  Future<TaskNote> updateNote({required int noteId, required String body}) =>
      _authorized(
        (token) => data.updateNote(token: token, noteId: noteId, body: body),
      );

  Future<void> deleteNote(int noteId) =>
      _authorized((token) => data.deleteNote(token: token, noteId: noteId));

  Future<TaskComment> updateComment({
    required int commentId,
    required String body,
  }) =>
      _authorized(
        (token) =>
            data.updateComment(token: token, commentId: commentId, body: body),
      );

  /// Deletes a comment and returns how many nested replies cascaded with it.
  Future<int> deleteComment(int commentId) => _authorized(
        (token) => data.deleteComment(token: token, commentId: commentId),
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
    final refreshToken = _requireTokens().refreshToken;
    try {
      _setTokens(await api.refresh(refreshToken));
    } on AuthApiException catch (error) {
      // A 401 here means the stored refresh token is dead (expired or already
      // rotated by another tab). Wipe memory + storage so the UI falls back to
      // the sign-in screen cleanly instead of looping on a bad credential.
      if (error.statusCode == 401) {
        _clearTokens();
      }
      rethrow;
    }
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
    // Persist the user (so the next load paints the shell immediately) and the
    // rotated refresh token (so [restore] can exchange it for a new access
    // token). The access token is short-lived and stays in memory only.
    _storage.write(user: tokens.user, refreshToken: tokens.refreshToken);
    // Covers every way a session begins — sign-in, reload restore, and token
    // refresh — and is a no-op once the channel is already open.
    _startBlockerChannel();
    notifyListeners();
  }

  void _clearTokens() {
    _tokens = null;
    _accessExpiresAt = null;
    _storage.clear();
    // Close the socket before the token goes, so it cannot try to reconnect
    // with credentials that no longer exist.
    _stopBlockerChannel();
    // Keep read-id state scoped to a signed-in session so a second account
    // signing in on the same page doesn't inherit the first user's "seen"
    // list.
    _readNotificationIds.clear();
    notifyListeners();
  }
}
