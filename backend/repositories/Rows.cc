#include "Rows.h"

#include <stdexcept>
#include <unordered_map>

namespace taskmanager::rows
{

TaskRecord task(const db::Statement &statement)
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
    return task;
}

TaskNoteRecord note(const db::Statement &statement)
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

CommentRecord comment(const db::Statement &statement)
{
    CommentRecord comment;
    comment.id = statement.int64Column(0);
    comment.taskId = statement.int64Column(1);
    comment.authorId = statement.int64Column(2);
    comment.parentCommentId = statement.optInt64Column(3);
    comment.body = statement.textColumn(4);
    comment.createdAt = statement.textColumn(5);
    comment.updatedAt = statement.textColumn(6);
    return comment;
}

ProjectRecord project(const db::Statement &statement)
{
    ProjectRecord project;
    project.id = statement.int64Column(0);
    project.name = statement.textColumn(1);
    project.description = statement.optTextColumn(2);
    project.createdById = statement.optInt64Column(3);
    project.createdAt = statement.textColumn(4);
    project.updatedAt = statement.textColumn(5);
    return project;
}

NotificationRecord notification(const db::Statement &statement)
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

UserRecord userSummary(const db::Statement &statement)
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

std::vector<TaskRecord> queryTasks(const db::Connection &connection,
                                   const std::string &whereOrderClause,
                                   std::optional<std::int64_t> bindValue)
{
    std::vector<TaskRecord> tasks;
    std::unordered_map<std::int64_t, std::size_t> indexById;
    {
        db::Statement statement(connection,
                                std::string("SELECT ") + kTaskColumns +
                                    " FROM tasks " + whereOrderClause);
        if (bindValue)
        {
            statement.bindInt64(1, *bindValue);
        }
        while (statement.step())
        {
            indexById.emplace(statement.int64Column(0), tasks.size());
            tasks.push_back(task(statement));
        }
    }
    if (tasks.empty())
    {
        return tasks;
    }

    // One query for every listed task's assignees instead of one per task.
    // It re-runs the same filter as a subquery, so ?1 binds the same value.
    // Ordered (assigned_at, user_id) like assigneeIds(), so each task's list
    // comes out in the same order either way.
    db::Statement assignees(
        connection,
        std::string("SELECT task_id, user_id FROM task_assignees WHERE "
                    "task_id IN (SELECT id FROM tasks ") +
            whereOrderClause + ") ORDER BY assigned_at, user_id");
    if (bindValue)
    {
        assignees.bindInt64(1, *bindValue);
    }
    while (assignees.step())
    {
        const auto entry = indexById.find(assignees.int64Column(0));
        if (entry != indexById.end())
        {
            tasks[entry->second].assigneeIds.push_back(assignees.int64Column(1));
        }
    }
    return tasks;
}

std::vector<std::int64_t> assigneeIds(const db::Connection &connection,
                                      std::int64_t taskId)
{
    db::Statement statement(connection,
                            "SELECT user_id FROM task_assignees WHERE "
                            "task_id = ?1 ORDER BY assigned_at, user_id");
    statement.bindInt64(1, taskId);
    std::vector<std::int64_t> ids;
    while (statement.step())
    {
        ids.push_back(statement.int64Column(0));
    }
    return ids;
}

TaskRecord taskById(const db::Connection &connection, std::int64_t id)
{
    auto found = findById(connection, kTaskColumns, "tasks", id, task);
    if (!found)
    {
        throw std::runtime_error("Task could not be read back");
    }
    found->assigneeIds = assigneeIds(connection, id);
    return *found;
}

void insertEvent(const db::Connection &connection,
                 std::int64_t taskId,
                 std::int64_t actorId,
                 const char *eventType,
                 const std::optional<std::string> &details)
{
    db::Statement insert(
        connection,
        "INSERT INTO task_events (task_id, actor_id, event_type, details) "
        "VALUES (?1, ?2, ?3, ?4)");
    insert.bindInt64(1, taskId);
    insert.bindInt64(2, actorId);
    insert.bindText(3, eventType);
    insert.bindOptText(4, details);
    insert.step();
}

NotificationRecord insertNotification(const db::Connection &connection,
                                      std::int64_t recipientId,
                                      std::int64_t actorId,
                                      std::int64_t taskId,
                                      const std::string &type,
                                      const std::string &message)
{
    db::Statement insert(
        connection,
        "INSERT INTO notifications (recipient_id, actor_id, task_id, "
        "notification_type, message) VALUES (?1, ?2, ?3, ?4, ?5)");
    insert.bindInt64(1, recipientId);
    insert.bindInt64(2, actorId);
    insert.bindInt64(3, taskId);
    insert.bindText(4, type);
    insert.bindText(5, message);
    insert.step();

    auto stored = findById(connection,
                           kNotificationColumns,
                           "notifications",
                           connection.lastInsertRowId(),
                           notification);
    if (!stored)
    {
        throw std::runtime_error("Created notification could not be read back");
    }
    return *stored;
}

}  // namespace taskmanager::rows
