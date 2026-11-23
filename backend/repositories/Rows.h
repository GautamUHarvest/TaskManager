#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"
#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

// Column lists, row mappers and shared write helpers for the task-domain
// repositories. Each SELECT that feeds a mapper must use the matching column
// list, in that order — the mappers read columns by position.
namespace taskmanager::rows
{

inline constexpr const char *kTaskColumns =
    "id, parent_task_id, project_id, title, description, status, type, "
    "discipline, due_at, start_at, created_by_id, version, created_at, "
    "updated_at, task_index";
inline constexpr const char *kNoteColumns =
    "id, task_id, author_id, body, created_at, updated_at";
inline constexpr const char *kCommentColumns =
    "id, task_id, author_id, parent_comment_id, body, created_at, updated_at";
inline constexpr const char *kProjectColumns =
    "id, name, description, created_by_id, created_at, updated_at";
inline constexpr const char *kNotificationColumns =
    "id, recipient_id, actor_id, task_id, notification_type, message, "
    "created_at, read_at";
// Public profile only: the directory never reads password hashes.
inline constexpr const char *kUserSummaryColumns =
    "id, employee_id, email, display_name";

// Mappers. TaskRecord::assigneeIds is NOT filled in by task() — it lives in a
// junction table; use loadAssignees() / taskById().
TaskRecord task(const db::Statement &statement);
TaskNoteRecord note(const db::Statement &statement);
CommentRecord comment(const db::Statement &statement);
ProjectRecord project(const db::Statement &statement);
NotificationRecord notification(const db::Statement &statement);
UserRecord userSummary(const db::Statement &statement);

// Reads a single row by id with the given column list and mapper, or nullopt.
template <typename Mapper>
auto findById(const db::Connection &connection,
              const char *columns,
              const char *table,
              std::int64_t id,
              Mapper mapper)
    -> std::optional<decltype(mapper(std::declval<const db::Statement &>()))>
{
    db::Statement statement(connection,
                            std::string("SELECT ") + columns + " FROM " +
                                table + " WHERE id = ?1");
    statement.bindInt64(1, id);
    if (!statement.step())
    {
        return std::nullopt;
    }
    return mapper(statement);
}

// Runs a task SELECT (built from kTaskColumns) and returns the tasks with
// their assignees filled in. `bindValue`, when present, is bound to ?1.
std::vector<TaskRecord> queryTasks(const db::Connection &connection,
                                   const std::string &whereOrderClause,
                                   std::optional<std::int64_t> bindValue);

// The task with its assignees. Throws std::runtime_error if it is missing —
// only for re-reading a row just written in the same transaction.
TaskRecord taskById(const db::Connection &connection, std::int64_t id);

std::vector<std::int64_t> assigneeIds(const db::Connection &connection,
                                      std::int64_t taskId);

// Appends to the task_events audit log. eventType must be allowed by the
// task_events CHECK constraint.
void insertEvent(const db::Connection &connection,
                 std::int64_t taskId,
                 std::int64_t actorId,
                 const char *eventType,
                 const std::optional<std::string> &details);

// Inserts a notification on an existing connection, so it can join a wider
// transaction, and returns the stored row.
NotificationRecord insertNotification(const db::Connection &connection,
                                      std::int64_t recipientId,
                                      std::int64_t actorId,
                                      std::int64_t taskId,
                                      const std::string &type,
                                      const std::string &message);

}  // namespace taskmanager::rows
