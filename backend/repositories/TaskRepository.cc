#include "TaskRepository.h"

#include "../common/Errors.h"
#include "Rows.h"

#include <string>
#include <utility>
#include <vector>

namespace taskmanager
{
namespace
{
constexpr const char *kNowTimestamp = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

void insertAssignees(const db::Connection &connection,
                     std::int64_t taskId,
                     const std::vector<std::int64_t> &userIds)
{
    for (const auto userId : userIds)
    {
        db::Statement insert(
            connection,
            "INSERT INTO task_assignees (task_id, user_id) VALUES (?1, ?2)");
        insert.bindInt64(1, taskId);
        insert.bindInt64(2, userId);
        insert.step();
    }
}

std::int64_t insertTask(const db::Connection &connection, const NewTask &task)
{
    db::Statement insert(
        connection,
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
    const std::int64_t taskId = connection.lastInsertRowId();
    insertAssignees(connection, taskId, task.assigneeIds);
    return taskId;
}

// Confirms the task exists before an UPDATE, which would otherwise succeed
// silently on zero rows.
void requireTask(const db::Connection &connection, std::int64_t taskId)
{
    db::Statement exists(connection, "SELECT 1 FROM tasks WHERE id = ?1");
    exists.bindInt64(1, taskId);
    if (!exists.step())
    {
        throw NotFoundError("Task not found");
    }
}

// Human-readable summary of which fields an edit touched, for the
// task_events details column (e.g. "Updated title, status, assignees").
std::string describeUpdate(const TaskUpdate &update)
{
    std::string summary;
    const auto add = [&summary](const char *name) {
        if (!summary.empty())
        {
            summary += ", ";
        }
        summary += name;
    };
    if (update.title) add("title");
    if (update.description) add("description");
    if (update.status) add("status");
    if (update.type) add("type");
    if (update.discipline) add("discipline");
    if (update.dueAt) add("due_at");
    if (update.startAt) add("start_at");
    if (update.assigneeIds) add("assignees");
    if (update.projectId) add("project");
    return "Updated " + summary;
}
}  // namespace

TaskRepository::TaskRepository(const db::Database &database)
    : database_(database)
{
}

TaskRecord TaskRepository::create(const NewTask &task)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid task: assignee or parent task does not exist, or a field "
        "violates a constraint",
        [&] {
            db::Transaction transaction(connection);
            const auto id = insertTask(connection, task);
            auto created = rows::taskById(connection, id);
            transaction.commit();
            return created;
        });
}

TaskRecord TaskRepository::createSubtask(const NewTask &task)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid subtask: assignee or parent task does not exist, or a field "
        "violates a constraint",
        [&] {
            db::Transaction transaction(connection);
            const auto id = insertTask(connection, task);
            if (task.parentTaskId)
            {
                rows::insertEvent(connection,
                                  *task.parentTaskId,
                                  task.createdById,
                                  "subtask_created",
                                  "Subtask #" + std::to_string(id) +
                                      " created");
            }
            auto created = rows::taskById(connection, id);
            transaction.commit();
            return created;
        });
}

TaskRecord TaskRepository::updateStatus(std::int64_t taskId,
                                        const std::string &status,
                                        std::int64_t actorId)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid status change: a field violates a constraint", [&] {
            db::Transaction transaction(connection);
            // Read the current status first: confirms the task exists and
            // gives the previous value for the event detail.
            std::string previousStatus;
            {
                db::Statement select(connection,
                                     "SELECT status FROM tasks WHERE id = ?1");
                select.bindInt64(1, taskId);
                if (!select.step())
                {
                    throw NotFoundError("Task not found");
                }
                previousStatus = select.textColumn(0);
            }

            db::Statement update(
                connection,
                std::string("UPDATE tasks SET status = ?1, version = version "
                            "+ 1, updated_at = ") +
                    kNowTimestamp + " WHERE id = ?2");
            update.bindText(1, status);
            update.bindInt64(2, taskId);
            update.step();

            rows::insertEvent(connection,
                              taskId,
                              actorId,
                              "status_changed",
                              previousStatus + " -> " + status);

            auto updated = rows::taskById(connection, taskId);
            transaction.commit();
            return updated;
        });
}

TaskRecord TaskRepository::update(const TaskUpdate &update,
                                  std::int64_t actorId)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid task update: assignee or project does not exist, or a field "
        "violates a constraint",
        [&] {
            db::Transaction transaction(connection);
            requireTask(connection, update.taskId);

            // Build the SET list from the engaged fields only, numbering
            // placeholders in the exact order they are bound below. version
            // and updated_at always move, so an assignee-only edit still
            // bumps them.
            std::string sql =
                std::string("UPDATE tasks SET version = version + 1, "
                            "updated_at = ") +
                kNowTimestamp;
            int placeholders = 0;
            const auto column = [&](const char *name) {
                sql += std::string(", ") + name + " = ?" +
                       std::to_string(++placeholders);
            };
            if (update.title) column("title");
            if (update.description) column("description");
            if (update.status) column("status");
            if (update.type) column("type");
            if (update.discipline) column("discipline");
            if (update.dueAt) column("due_at");
            if (update.startAt) column("start_at");
            if (update.projectId) column("project_id");
            sql += " WHERE id = ?" + std::to_string(placeholders + 1);

            {
                db::Statement statement(connection, sql);
                int bound = 0;
                if (update.title) statement.bindText(++bound, *update.title);
                if (update.description)
                    statement.bindOptText(++bound, *update.description);
                if (update.status) statement.bindText(++bound, *update.status);
                if (update.type) statement.bindText(++bound, *update.type);
                if (update.discipline)
                    statement.bindText(++bound, *update.discipline);
                if (update.dueAt) statement.bindOptText(++bound, *update.dueAt);
                if (update.startAt)
                    statement.bindOptText(++bound, *update.startAt);
                if (update.projectId)
                    statement.bindInt64(++bound, *update.projectId);
                statement.bindInt64(++bound, update.taskId);
                statement.step();
            }

            // Assignees live in a junction table, so a change is a full
            // replace.
            if (update.assigneeIds)
            {
                db::Statement clear(
                    connection, "DELETE FROM task_assignees WHERE task_id = ?1");
                clear.bindInt64(1, update.taskId);
                clear.step();
                insertAssignees(connection, update.taskId, *update.assigneeIds);
            }

            rows::insertEvent(connection,
                              update.taskId,
                              actorId,
                              "updated",
                              describeUpdate(update));

            auto updated = rows::taskById(connection, update.taskId);
            transaction.commit();
            return updated;
        });
}

void TaskRepository::remove(std::int64_t taskId)
{
    auto connection = database_.connect();
    db::mapConstraintError(
        "Cannot delete this task: another record still references it", [&] {
            db::Transaction transaction(connection);
            // task_notes, task_events and notifications reference tasks with
            // ON DELETE RESTRICT (migration 001), so they are cleared by hand
            // and in this order. task_assignees and comments are ON DELETE
            // CASCADE (migration 006) — and comment replies cascade from
            // their parent comment.
            for (const char *sql :
                 {"DELETE FROM task_notes WHERE task_id = ?1",
                  "DELETE FROM task_events WHERE task_id = ?1",
                  "DELETE FROM notifications WHERE task_id = ?1",
                  "DELETE FROM tasks WHERE id = ?1"})
            {
                db::Statement statement(connection, sql);
                statement.bindInt64(1, taskId);
                statement.step();
            }
            transaction.commit();
        });
}

BlockerRaised TaskRepository::raiseBlocker(
    std::int64_t taskId,
    std::int64_t actorId,
    std::int64_t responsibleId,
    const std::string &eventDetail,
    const std::string &notificationMessage)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid blocker: the task or the responsible member does not exist",
        [&] {
            db::Transaction transaction(connection);
            requireTask(connection, taskId);

            db::Statement update(
                connection,
                std::string("UPDATE tasks SET status = 'blocked', version = "
                            "version + 1, updated_at = ") +
                    kNowTimestamp + " WHERE id = ?1");
            update.bindInt64(1, taskId);
            update.step();

            rows::insertEvent(connection, taskId, actorId, "blocked", eventDetail);

            BlockerRaised raised;
            raised.notification =
                rows::insertNotification(connection,
                                         responsibleId,
                                         actorId,
                                         taskId,
                                         kBlockerNotificationType,
                                         notificationMessage);
            raised.task = rows::taskById(connection, taskId);
            transaction.commit();
            return raised;
        });
}

std::optional<TaskRecord> TaskRepository::find(std::int64_t id)
{
    auto connection = database_.connect();
    auto tasks = rows::queryTasks(connection, "WHERE id = ?1", id);
    if (tasks.empty())
    {
        return std::nullopt;
    }
    return std::move(tasks.front());
}

std::int64_t TaskRepository::countSubtasks(std::int64_t parentTaskId)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection, "SELECT COUNT(*) FROM tasks WHERE parent_task_id = ?1");
    statement.bindInt64(1, parentTaskId);
    return statement.step() ? statement.int64Column(0) : 0;
}

std::vector<TaskRecord> TaskRepository::listSubtasks(std::int64_t parentTaskId)
{
    auto connection = database_.connect();
    return rows::queryTasks(connection,
                            "WHERE parent_task_id = ?1 ORDER BY created_at, id",
                            parentTaskId);
}

std::vector<TaskRecord> TaskRepository::listAll()
{
    auto connection = database_.connect();
    return rows::queryTasks(connection, "ORDER BY created_at DESC", std::nullopt);
}

std::vector<TaskRecord> TaskRepository::listByAssignee(std::int64_t userId)
{
    auto connection = database_.connect();
    return rows::queryTasks(
        connection,
        "WHERE id IN (SELECT task_id FROM task_assignees WHERE user_id = ?1) "
        "ORDER BY due_at IS NULL, due_at, created_at DESC",
        userId);
}

std::vector<TaskRecord> TaskRepository::listCompleted()
{
    auto connection = database_.connect();
    return rows::queryTasks(connection,
                            "WHERE status = 'done' ORDER BY updated_at DESC",
                            std::nullopt);
}

std::vector<TaskRecord> TaskRepository::listByProject(std::int64_t projectId)
{
    auto connection = database_.connect();
    return rows::queryTasks(connection,
                            "WHERE project_id = ?1 ORDER BY created_at DESC",
                            projectId);
}

}  // namespace taskmanager
