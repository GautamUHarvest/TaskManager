#include "TaskRepository.h"

#include <sqlite3.h>

#include <stdexcept>
#include <utility>

namespace taskmanager
{
namespace
{ 
// NOTE: Connection/Statement duplicate the helpers in AuthRepository.cc on
// purpose for now. Deduplicating them into a shared SQLite utility is part of
// the planned modularity pass.
class Connection
{
  public:
    explicit Connection(const std::string &path)
    {
        const int result = sqlite3_open_v2(
            path.c_str(),
            &database_,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nullptr);
        if (result != SQLITE_OK)
        {
            const std::string message =
                database_ ? sqlite3_errmsg(database_) : "SQLite open failed";
            if (database_)
            {
                sqlite3_close(database_);
                database_ = nullptr;
            }
            throw std::runtime_error(message);
        }
        sqlite3_busy_timeout(database_, 5000);
        execute("PRAGMA foreign_keys = ON");
    }

    ~Connection()
    {
        if (database_)
        {
            sqlite3_close(database_);
        }
    }

    Connection(const Connection &) = delete;
    Connection &operator=(const Connection &) = delete;

    sqlite3 *get() const
    {
        return database_;
    }

    void execute(const std::string &sql) const
    {
        char *error = nullptr;
        if (sqlite3_exec(database_, sql.c_str(), nullptr, nullptr, &error) !=
            SQLITE_OK)
        {
            std::string message = error ? error : sqlite3_errmsg(database_);
            sqlite3_free(error);
            throw std::runtime_error("SQLite operation failed: " + message);
        }
    }

  private:
    sqlite3 *database_{nullptr};
};

class Statement
{
  public:
    Statement(sqlite3 *database, const std::string &sql) : database_(database)
    {
        if (sqlite3_prepare_v2(database, sql.c_str(), -1, &statement_, nullptr) !=
            SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database));
        }
    }

    ~Statement()
    {
        sqlite3_finalize(statement_);
    }

    Statement(const Statement &) = delete;
    Statement &operator=(const Statement &) = delete;

    void bindInt64(int index, std::int64_t value)
    {
        if (sqlite3_bind_int64(statement_, index, value) != SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
    }

    void bindText(int index, const std::string &value)
    {
        if (sqlite3_bind_text(statement_,
                              index,
                              value.data(),
                              static_cast<int>(value.size()),
                              SQLITE_TRANSIENT) != SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
    }

    void bindNull(int index)
    {
        if (sqlite3_bind_null(statement_, index) != SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
    }

    void bindOptText(int index, const std::optional<std::string> &value)
    {
        value ? bindText(index, *value) : bindNull(index);
    }

    void bindOptInt64(int index, const std::optional<std::int64_t> &value)
    {
        value ? bindInt64(index, *value) : bindNull(index);
    }

    int step()
    {
        const int result = sqlite3_step(statement_);
        if (result != SQLITE_ROW && result != SQLITE_DONE)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
        return result;
    }

    bool isNull(int index) const
    {
        return sqlite3_column_type(statement_, index) == SQLITE_NULL;
    }

    std::int64_t int64Column(int index) const
    {
        return sqlite3_column_int64(statement_, index);
    }

    std::string textColumn(int index) const
    {
        const auto *text = sqlite3_column_text(statement_, index);
        return text ? reinterpret_cast<const char *>(text) : std::string();
    }

    std::optional<std::int64_t> optInt64Column(int index) const
    {
        if (isNull(index))
        {
            return std::nullopt;
        }
        return int64Column(index);
    }

    std::optional<std::string> optTextColumn(int index) const
    {
        if (isNull(index))
        {
            return std::nullopt;
        }
        return textColumn(index);
    }

  private:
    sqlite3 *database_;
    sqlite3_stmt *statement_{nullptr};
};

UserRecord userFromStatement(const Statement &statement)
{
    UserRecord user;
    user.id = statement.int64Column(0);
    user.employeeId = statement.textColumn(1);
    user.email = statement.textColumn(2);
    user.displayName = statement.textColumn(3);
    user.passwordHash = std::string();
    user.active = true;
    user.emailVerified = true;
    return user;
}

TaskRecord taskFromStatement(const Statement &statement)
{
    TaskRecord task;
    task.id = statement.int64Column(0);
    task.parentTaskId = statement.optInt64Column(1);
    task.projectId = statement.int64Column(2);
    task.title = statement.textColumn(3);
    task.description = statement.optTextColumn(4);
    task.status = statement.textColumn(5);
    task.type = statement.textColumn(6);
    task.discipline = statement.textColumn(7);
    task.dueAt = statement.optTextColumn(8);
    task.startAt = statement.optTextColumn(9);
    task.createdById = statement.int64Column(10);
    task.version = statement.int64Column(11);
    task.createdAt = statement.textColumn(12);
    task.updatedAt = statement.textColumn(13);
    // assigneeIds are loaded separately via listAssigneeIds
    return task;
}

NotificationRecord notificationFromStatement(const Statement &statement)
{
    NotificationRecord notification;
    notification.id = statement.int64Column(0);
    notification.recipientId = statement.int64Column(1);
    notification.actorId = statement.int64Column(2);
    notification.taskId = statement.int64Column(3);
    notification.notificationType = statement.textColumn(4);
    notification.message = statement.textColumn(5);
    notification.createdAt = statement.textColumn(6);
    notification.readAt = statement.optTextColumn(7);
    return notification;
}

constexpr const char *kTaskColumns =
    "id, parent_task_id, project_id, title, description, status, type, "
    "discipline, due_at, start_at, created_by_id, version, created_at, "
    "updated_at";

std::vector<std::int64_t> loadAssigneeIds(Connection &connection,
                                          std::int64_t taskId)
{
    Statement stmt(connection.get(),
                   "SELECT user_id FROM task_assignees WHERE task_id = ?1 "
                   "ORDER BY assigned_at, user_id");
    stmt.bindInt64(1, taskId);
    std::vector<std::int64_t> ids;
    while (stmt.step() == SQLITE_ROW)
    {
        ids.push_back(stmt.int64Column(0));
    }
    return ids;
}

std::vector<TaskRecord> queryTasks(const std::string &databasePath,
                                   const std::string &whereOrderClause,
                                   std::optional<std::int64_t> bindValue)
{
    Connection connection(databasePath);
    Statement statement(connection.get(),
                        std::string("SELECT ") + kTaskColumns +
                            " FROM tasks " + whereOrderClause);
    if (bindValue)
    {
        statement.bindInt64(1, *bindValue);
    }
    std::vector<TaskRecord> tasks;
    while (statement.step() == SQLITE_ROW)
    {
        tasks.push_back(taskFromStatement(statement));
    }
    for (auto &task : tasks)
    {
        task.assigneeIds = loadAssigneeIds(connection, task.id);
    }
    return tasks;
}

TaskRecord taskById(Connection &connection, std::int64_t id)
{
    Statement statement(connection.get(),
                        std::string("SELECT ") + kTaskColumns +
                            " FROM tasks WHERE id = ?1");
    statement.bindInt64(1, id);
    if (statement.step() != SQLITE_ROW)
    {
        throw std::runtime_error("Created task could not be read back");
    }
    auto task = taskFromStatement(statement);
    task.assigneeIds = loadAssigneeIds(connection, task.id);
    return task;
}

TaskNoteRecord noteFromStatement(const Statement &statement)
{
    TaskNoteRecord note;
    note.id = statement.int64Column(0);
    note.taskId = statement.int64Column(1);
    note.authorId = statement.int64Column(2);
    note.body = statement.textColumn(3);
    note.createdAt = statement.textColumn(4);
    note.updatedAt = statement.textColumn(5);
    return note;
}

constexpr const char *kNoteColumns =
    "id, task_id, author_id, body, created_at, updated_at";

std::int64_t insertTask(Connection &connection, const NewTask &task)
{
    Statement insert(
        connection.get(),
        "INSERT INTO tasks (title, description, status, type, discipline, "
        "due_at, start_at, parent_task_id, created_by_id, project_id) "
        "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)");
    insert.bindText(1, task.title);
    insert.bindOptText(2, task.description);
    insert.bindText(3, task.status);
    insert.bindText(4, task.type);
    insert.bindText(5, task.discipline);
    insert.bindOptText(6, task.dueAt);
    insert.bindOptText(7, task.startAt);
    insert.bindOptInt64(8, task.parentTaskId);
    insert.bindInt64(9, task.createdById);
    insert.bindInt64(10, task.projectId);
    insert.step();
    const std::int64_t taskId = sqlite3_last_insert_rowid(connection.get());

    for (const auto userId : task.assigneeIds)
    {
        Statement assignee(
            connection.get(),
            "INSERT INTO task_assignees (task_id, user_id) VALUES (?1, ?2)");
        assignee.bindInt64(1, taskId);
        assignee.bindInt64(2, userId);
        assignee.step();
    }

    return taskId;
}

// Appends a row to the task_events audit log. event_type must be one of the
// values allowed by the task_events CHECK constraint.
void insertEvent(Connection &connection,
                 std::int64_t taskId,
                 std::int64_t actorId,
                 const char *eventType,
                 const std::optional<std::string> &details)
{
    Statement insert(
        connection.get(),
        "INSERT INTO task_events (task_id, actor_id, event_type, details) "
        "VALUES (?1, ?2, ?3, ?4)");
    insert.bindInt64(1, taskId);
    insert.bindInt64(2, actorId);
    insert.bindText(3, eventType);
    insert.bindOptText(4, details);
    insert.step();
}
}  // namespace

TaskRepository::TaskRepository(std::string databasePath)
    : databasePath_(std::move(databasePath))
{
    if (databasePath_.empty())
    {
        throw std::invalid_argument("Database path is required");
    }
}

TaskRecord TaskRepository::createTask(const NewTask &task)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        const std::int64_t id = insertTask(connection, task);
        auto created = taskById(connection, id);
        connection.execute("COMMIT");
        return created;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument(
                "Invalid task: assignee or parent task does not exist, or a "
                "field violates a constraint");
        }
        throw;
    }
}

TaskRecord TaskRepository::createSubtask(const NewTask &task)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        const std::int64_t id = insertTask(connection, task);
        if (task.parentTaskId)
        {
            insertEvent(connection,
                        *task.parentTaskId,
                        task.createdById,
                        "subtask_created",
                        std::string("Subtask #") + std::to_string(id) +
                            " created");
        }
        auto created = taskById(connection, id);
        connection.execute("COMMIT");
        return created;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument(
                "Invalid subtask: assignee or parent task does not exist, or a "
                "field violates a constraint");
        }
        throw;
    }
}

TaskNoteRecord TaskRepository::addNote(const NewTaskNote &note)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        Statement insert(
            connection.get(),
            "INSERT INTO task_notes (task_id, author_id, body) "
            "VALUES (?1, ?2, ?3)");
        insert.bindInt64(1, note.taskId);
        insert.bindInt64(2, note.authorId);
        insert.bindText(3, note.body);
        insert.step();

        const std::int64_t id = sqlite3_last_insert_rowid(connection.get());
        Statement select(connection.get(),
                        std::string("SELECT ") + kNoteColumns +
                            " FROM task_notes WHERE id = ?1");
        select.bindInt64(1, id);
        if (select.step() != SQLITE_ROW)
        {
            throw std::runtime_error("Created note could not be read back");
        }
        auto created = noteFromStatement(select);
        connection.execute("COMMIT");
        return created;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument("Invalid note: the task does not exist");
        }
        throw;
    }
}

TaskRecord TaskRepository::updateStatus(std::int64_t taskId,
                                        const std::string &status,
                                        std::int64_t actorId)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        // Read the current status first: confirms the task exists (otherwise a
        // 0-row UPDATE would silently succeed) and gives the previous value for
        // the event detail.
        std::string previousStatus;
        {
            Statement select(connection.get(),
                            "SELECT status FROM tasks WHERE id = ?1");
            select.bindInt64(1, taskId);
            if (select.step() != SQLITE_ROW)
            {
                throw std::invalid_argument("Task not found");
            }
            previousStatus = select.textColumn(0);
        }

        Statement update(
            connection.get(),
            "UPDATE tasks SET status = ?1, version = version + 1, "
            "updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
            "WHERE id = ?2");
        update.bindText(1, status);
        update.bindInt64(2, taskId);
        update.step();

        insertEvent(connection,
                    taskId,
                    actorId,
                    "status_changed",
                    previousStatus + " -> " + status);

        auto updated = taskById(connection, taskId);
        connection.execute("COMMIT");
        return updated;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument(
                "Invalid status change: a field violates a constraint");
        }
        throw;
    }
}

std::optional<TaskRecord> TaskRepository::findTask(std::int64_t id)
{
    auto tasks = queryTasks(databasePath_, "WHERE id = ?1", id);
    if (tasks.empty())
    {
        return std::nullopt;
    }
    return tasks.front();
}

std::vector<TaskRecord> TaskRepository::listSubtasks(std::int64_t parentTaskId)
{
    return queryTasks(databasePath_,
                      "WHERE parent_task_id = ?1 ORDER BY created_at, id",
                      parentTaskId);
}

std::vector<TaskNoteRecord> TaskRepository::listNotes(std::int64_t taskId)
{
    Connection connection(databasePath_);
    Statement statement(connection.get(),
                        std::string("SELECT ") + kNoteColumns +
                            " FROM task_notes WHERE task_id = ?1 "
                            "ORDER BY created_at, id");
    statement.bindInt64(1, taskId);
    std::vector<TaskNoteRecord> notes;
    while (statement.step() == SQLITE_ROW)
    {
        notes.push_back(noteFromStatement(statement));
    }
    return notes;
}

std::vector<UserRecord> TaskRepository::listUsers()
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, employee_id, email, display_name FROM users "
        "WHERE is_active = 1 ORDER BY display_name COLLATE NOCASE");
    std::vector<UserRecord> users;
    while (statement.step() == SQLITE_ROW)
    {
        users.push_back(userFromStatement(statement));
    }
    return users;
}

std::vector<NotificationRecord> TaskRepository::listNotifications(
    std::int64_t recipientId)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, recipient_id, actor_id, task_id, notification_type, "
        "message, created_at, read_at FROM notifications "
        "WHERE recipient_id = ?1 ORDER BY created_at DESC");
    statement.bindInt64(1, recipientId);
    std::vector<NotificationRecord> notifications;
    while (statement.step() == SQLITE_ROW)
    {
        notifications.push_back(notificationFromStatement(statement));
    }
    return notifications;
}

std::vector<TaskRecord> TaskRepository::listAllTasks()
{
    return queryTasks(databasePath_, "ORDER BY created_at DESC", std::nullopt);
}

std::vector<TaskRecord> TaskRepository::listTasksByAssignee(
    std::int64_t assigneeId)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        std::string("SELECT ") + kTaskColumns +
            " FROM tasks WHERE id IN "
            "(SELECT task_id FROM task_assignees WHERE user_id = ?1) "
            "ORDER BY due_at IS NULL, due_at, created_at DESC");
    statement.bindInt64(1, assigneeId);
    std::vector<TaskRecord> tasks;
    while (statement.step() == SQLITE_ROW)
    {
        tasks.push_back(taskFromStatement(statement));
    }
    for (auto &task : tasks)
    {
        task.assigneeIds = loadAssigneeIds(connection, task.id);
    }
    return tasks;
}

std::vector<TaskRecord> TaskRepository::listCompletedTasks()
{
    return queryTasks(databasePath_,
                      "WHERE status = 'done' ORDER BY updated_at DESC",
                      std::nullopt);
}

std::vector<TaskRecord> TaskRepository::listTasksByProject(
    std::int64_t projectId)
{
    return queryTasks(databasePath_,
                      "WHERE project_id = ?1 ORDER BY created_at DESC",
                      projectId);
}

// --- Projects ---

ProjectRecord TaskRepository::createProject(const NewProject &project)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        Statement insert(
            connection.get(),
            "INSERT INTO projects (name, description, created_by_id) "
            "VALUES (?1, ?2, ?3)");
        insert.bindText(1, project.name);
        insert.bindOptText(2, project.description);
        insert.bindInt64(3, project.createdById);
        insert.step();

        const std::int64_t id = sqlite3_last_insert_rowid(connection.get());
        Statement select(
            connection.get(),
            "SELECT id, name, description, created_by_id, created_at, "
            "updated_at FROM projects WHERE id = ?1");
        select.bindInt64(1, id);
        if (select.step() != SQLITE_ROW)
        {
            throw std::runtime_error("Created project could not be read back");
        }
        ProjectRecord record;
        record.id = select.int64Column(0);
        record.name = select.textColumn(1);
        record.description = select.optTextColumn(2);
        record.createdById = select.optInt64Column(3);
        record.createdAt = select.textColumn(4);
        record.updatedAt = select.textColumn(5);
        connection.execute("COMMIT");
        return record;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument(
                "A project with that name already exists");
        }
        throw;
    }
}

std::vector<ProjectRecord> TaskRepository::listProjects()
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, name, description, created_by_id, created_at, updated_at "
        "FROM projects ORDER BY name COLLATE NOCASE");
    std::vector<ProjectRecord> projects;
    while (statement.step() == SQLITE_ROW)
    {
        ProjectRecord record;
        record.id = statement.int64Column(0);
        record.name = statement.textColumn(1);
        record.description = statement.optTextColumn(2);
        record.createdById = statement.optInt64Column(3);
        record.createdAt = statement.textColumn(4);
        record.updatedAt = statement.textColumn(5);
        projects.push_back(record);
    }
    return projects;
}

std::optional<ProjectRecord> TaskRepository::findProject(std::int64_t id)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, name, description, created_by_id, created_at, updated_at "
        "FROM projects WHERE id = ?1");
    statement.bindInt64(1, id);
    if (statement.step() != SQLITE_ROW)
    {
        return std::nullopt;
    }
    ProjectRecord record;
    record.id = statement.int64Column(0);
    record.name = statement.textColumn(1);
    record.description = statement.optTextColumn(2);
    record.createdById = statement.optInt64Column(3);
    record.createdAt = statement.textColumn(4);
    record.updatedAt = statement.textColumn(5);
    return record;
}

// --- Comments ---

CommentRecord TaskRepository::addComment(const NewComment &comment)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        Statement insert(
            connection.get(),
            "INSERT INTO comments (task_id, author_id, parent_comment_id, body)"
            " VALUES (?1, ?2, ?3, ?4)");
        insert.bindInt64(1, comment.taskId);
        insert.bindInt64(2, comment.authorId);
        insert.bindOptInt64(3, comment.parentCommentId);
        insert.bindText(4, comment.body);
        insert.step();

        const std::int64_t id = sqlite3_last_insert_rowid(connection.get());
        Statement select(
            connection.get(),
            "SELECT id, task_id, author_id, parent_comment_id, body, "
            "created_at, updated_at FROM comments WHERE id = ?1");
        select.bindInt64(1, id);
        if (select.step() != SQLITE_ROW)
        {
            throw std::runtime_error("Created comment could not be read back");
        }
        CommentRecord record;
        record.id = select.int64Column(0);
        record.taskId = select.int64Column(1);
        record.authorId = select.int64Column(2);
        record.parentCommentId = select.optInt64Column(3);
        record.body = select.textColumn(4);
        record.createdAt = select.textColumn(5);
        record.updatedAt = select.textColumn(6);
        connection.execute("COMMIT");
        return record;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw std::invalid_argument(
                "Invalid comment: the task or parent comment does not exist");
        }
        throw;
    }
}

std::vector<CommentRecord> TaskRepository::listComments(std::int64_t taskId)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, task_id, author_id, parent_comment_id, body, created_at, "
        "updated_at FROM comments WHERE task_id = ?1 ORDER BY created_at, id");
    statement.bindInt64(1, taskId);
    std::vector<CommentRecord> comments;
    while (statement.step() == SQLITE_ROW)
    {
        CommentRecord record;
        record.id = statement.int64Column(0);
        record.taskId = statement.int64Column(1);
        record.authorId = statement.int64Column(2);
        record.parentCommentId = statement.optInt64Column(3);
        record.body = statement.textColumn(4);
        record.createdAt = statement.textColumn(5);
        record.updatedAt = statement.textColumn(6);
        comments.push_back(record);
    }
    return comments;
}

std::optional<CommentRecord> TaskRepository::findComment(std::int64_t id)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, task_id, author_id, parent_comment_id, body, created_at, "
        "updated_at FROM comments WHERE id = ?1");
    statement.bindInt64(1, id);
    if (statement.step() != SQLITE_ROW)
    {
        return std::nullopt;
    }
    CommentRecord record;
    record.id = statement.int64Column(0);
    record.taskId = statement.int64Column(1);
    record.authorId = statement.int64Column(2);
    record.parentCommentId = statement.optInt64Column(3);
    record.body = statement.textColumn(4);
    record.createdAt = statement.textColumn(5);
    record.updatedAt = statement.textColumn(6);
    return record;
}

// --- Notifications ---

void TaskRepository::createNotification(std::int64_t recipientId,
                                        std::int64_t actorId,
                                        std::int64_t taskId,
                                        const std::string &type,
                                        const std::string &message)
{
    Connection connection(databasePath_);
    Statement insert(
        connection.get(),
        "INSERT INTO notifications (recipient_id, actor_id, task_id, "
        "notification_type, message) VALUES (?1, ?2, ?3, ?4, ?5)");
    insert.bindInt64(1, recipientId);
    insert.bindInt64(2, actorId);
    insert.bindInt64(3, taskId);
    insert.bindText(4, type);
    insert.bindText(5, message);
    insert.step();
}

std::vector<std::int64_t> TaskRepository::listAssigneeIds(std::int64_t taskId)
{
    Connection connection(databasePath_);
    return loadAssigneeIds(connection, taskId);
}

}  // namespace taskmanager
