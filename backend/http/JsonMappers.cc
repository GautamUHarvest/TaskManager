#include "JsonMappers.h"

#include <optional>
#include <string>

namespace taskmanager::http
{
namespace
{
Json::Value nullable(const std::optional<std::string> &value)
{
    return value ? Json::Value(*value) : Json::Value(Json::nullValue);
}

Json::Value nullable(const std::optional<std::int64_t> &value)
{
    return value ? Json::Value(Json::Int64(*value))
                 : Json::Value(Json::nullValue);
}
}  // namespace

Json::Value toJson(const UserRecord &user)
{
    Json::Value body;
    body["id"] = Json::Int64(user.id);
    body["employee_id"] = user.employeeId;
    body["email"] = user.email;
    body["display_name"] = user.displayName;
    return body;
}

Json::Value toJson(const ProjectRecord &project)
{
    Json::Value body;
    body["id"] = Json::Int64(project.id);
    body["name"] = project.name;
    body["description"] = nullable(project.description);
    body["created_by_id"] = nullable(project.createdById);
    body["created_at"] = project.createdAt;
    body["updated_at"] = project.updatedAt;
    return body;
}

Json::Value toJson(const TaskRecord &task)
{
    Json::Value body;
    body["id"] = Json::Int64(task.id);
    body["parent_task_id"] = nullable(task.parentTaskId);
    body["project_id"] = Json::Int64(task.projectId);
    body["title"] = task.title;
    body["description"] = nullable(task.description);
    body["status"] = task.status;
    body["type"] = task.type;
    body["discipline"] = task.discipline;
    body["due_at"] = nullable(task.dueAt);
    body["start_at"] = nullable(task.startAt);
    body["index"] = nullable(task.taskIndex);
    Json::Value assigneeIds(Json::arrayValue);
    for (const auto id : task.assigneeIds)
    {
        assigneeIds.append(Json::Int64(id));
    }
    body["assignee_ids"] = assigneeIds;
    body["created_by_id"] = Json::Int64(task.createdById);
    body["version"] = Json::Int64(task.version);
    body["created_at"] = task.createdAt;
    body["updated_at"] = task.updatedAt;
    return body;
}

Json::Value toJson(const TaskNoteRecord &note)
{
    Json::Value body;
    body["id"] = Json::Int64(note.id);
    body["task_id"] = Json::Int64(note.taskId);
    body["author_id"] = Json::Int64(note.authorId);
    body["body"] = note.body;
    body["created_at"] = note.createdAt;
    body["updated_at"] = note.updatedAt;
    return body;
}

Json::Value toJson(const CommentRecord &comment)
{
    Json::Value body;
    body["id"] = Json::Int64(comment.id);
    body["task_id"] = Json::Int64(comment.taskId);
    body["author_id"] = Json::Int64(comment.authorId);
    body["parent_comment_id"] = nullable(comment.parentCommentId);
    body["body"] = comment.body;
    body["created_at"] = comment.createdAt;
    body["updated_at"] = comment.updatedAt;
    return body;
}

Json::Value toJson(const NotificationRecord &notification)
{
    Json::Value body;
    body["id"] = Json::Int64(notification.id);
    body["recipient_id"] = Json::Int64(notification.recipientId);
    body["actor_id"] = Json::Int64(notification.actorId);
    body["task_id"] = Json::Int64(notification.taskId);
    body["notification_type"] = notification.notificationType;
    body["message"] = notification.message;
    body["created_at"] = notification.createdAt;
    body["read_at"] = nullable(notification.readAt);
    return body;
}

}  // namespace taskmanager::http
