/// The five task states the backend accepts (see API §3).
enum TaskStatus {
  todo('todo', 'To do'),
  inProgress('in_progress', 'In progress'),
  blocked('blocked', 'Blocked'),
  done('done', 'Done'),
  cancelled('cancelled', 'Cancelled');

  const TaskStatus(this.wire, this.label);

  /// Value sent to / received from the API.
  final String wire;

  /// Human-readable label for the UI.
  final String label;

  static TaskStatus fromWire(String? value) => TaskStatus.values.firstWhere(
        (status) => status.wire == value,
        orElse: () => TaskStatus.todo,
      );
}

/// Kind of work this task represents. Backend default is `decide` ("to be
/// decided") when not specified.
enum TaskType {
  decide('decide', 'To be decided'),
  design('design', 'Design'),
  test('test', 'Test'),
  measure('measure', 'Measure'),
  select('select', 'Select'),
  buy('buy', 'Buy'),
  admin('admin', 'Admin'),
  code('code', 'Code'),
  make('make', 'Make'),
  data('data', 'Data'),
  doc('doc', 'Doc'),
  integrate('integrate', 'Integrate');

  const TaskType(this.wire, this.label);

  final String wire;
  final String label;

  static TaskType fromWire(String? value) => TaskType.values.firstWhere(
        (type) => type.wire == value,
        orElse: () => TaskType.decide,
      );
}

/// Engineering discipline the task falls under. Backend default is `decide`.
enum TaskDiscipline {
  decide('decide', 'To be decided'),
  mechanical('mechanical', 'Mechanical'),
  electronics('electronics', 'Electronics'),
  software('software', 'Software'),
  serverBackend('server_backend', 'Server / Backend'),
  communications('communications', 'Communications'),
  embedded('embedded', 'Embedded'),
  controlSystems('control_systems', 'Control systems'),
  projectManagement('project_management', 'Project management'),
  operations('operations', 'Operations'),
  payments('payments', 'Payments'),
  systemsIntegration('systems_integration', 'Systems integration'),
  frontend('frontend', 'Frontend');

  const TaskDiscipline(this.wire, this.label);

  final String wire;
  final String label;

  static TaskDiscipline fromWire(String? value) =>
      TaskDiscipline.values.firstWhere(
        (discipline) => discipline.wire == value,
        orElse: () => TaskDiscipline.decide,
      );
}

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

class Task {
  const Task({
    required this.id,
    this.parentTaskId,
    required this.title,
    this.description,
    required this.status,
    this.type = TaskType.decide,
    this.discipline = TaskDiscipline.decide,
    this.startAt,
    this.dueAt,
    this.assigneeId,
    this.createdById,
    this.version = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as int,
        parentTaskId: json['parent_task_id'] as int?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        status: TaskStatus.fromWire(json['status'] as String?),
        type: TaskType.fromWire(json['type'] as String?),
        discipline: TaskDiscipline.fromWire(json['discipline'] as String?),
        startAt: _parseDate(json['start_at']),
        dueAt: _parseDate(json['due_at']),
        assigneeId: json['assignee_id'] as int?,
        createdById: json['created_by_id'] as int?,
        version: json['version'] as int? ?? 0,
        createdAt: _parseDate(json['created_at']),
        updatedAt: _parseDate(json['updated_at']),
      );

  final int id;
  final int? parentTaskId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskType type;
  final TaskDiscipline discipline;
  final DateTime? startAt;
  final DateTime? dueAt;
  final int? assigneeId;
  final int? createdById;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A free-text note attached to a task (see API `/task/note` and the `notes`
/// array returned by `/task/detail`). `author_id` is the user who wrote it.
class TaskNote {
  const TaskNote({
    required this.id,
    required this.taskId,
    this.authorId,
    required this.body,
    this.createdAt,
    this.updatedAt,
  });

  factory TaskNote.fromJson(Map<String, dynamic> json) => TaskNote(
        id: json['id'] as int,
        taskId: json['task_id'] as int,
        authorId: json['author_id'] as int?,
        body: json['body'] as String? ?? '',
        createdAt: _parseDate(json['created_at']),
        updatedAt: _parseDate(json['updated_at']),
      );

  final int id;
  final int taskId;
  final int? authorId;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// The payload of `GET /task/detail`: a task with its direct children and its
/// notes. `subtasks` are one level deep (oldest first); `notes` oldest first.
class TaskDetail {
  const TaskDetail({
    required this.task,
    required this.subtasks,
    required this.notes,
  });

  factory TaskDetail.fromJson(Map<String, dynamic> json) => TaskDetail(
        task: Task.fromJson(json['task'] as Map<String, dynamic>),
        subtasks: (json['subtasks'] as List<dynamic>? ?? const [])
            .map((item) => Task.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        notes: (json['notes'] as List<dynamic>? ?? const [])
            .map((item) => TaskNote.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final Task task;
  final List<Task> subtasks;
  final List<TaskNote> notes;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    this.actorId,
    this.taskId,
    required this.type,
    required this.message,
    this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        recipientId: json['recipient_id'] as int,
        actorId: json['actor_id'] as int?,
        taskId: json['task_id'] as int?,
        type: json['notification_type'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: _parseDate(json['created_at']),
        readAt: _parseDate(json['read_at']),
      );

  final int id;
  final int recipientId;
  final int? actorId;
  final int? taskId;
  final String type;
  final String message;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}
