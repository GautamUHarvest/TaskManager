#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

struct ProjectRecord
{
    std::int64_t id;
    std::string name;
    std::optional<std::string> description;
    // Null for the built-in default project (no human creator); set to the
    // authenticated user's id for user-created projects.
    std::optional<std::int64_t> createdById;
    std::string createdAt;
    std::string updatedAt;
};

struct NewProject
{
    std::int64_t createdById;
    std::string name;
    std::optional<std::string> description;
};

struct TaskRecord
{
    std::int64_t id;
    std::optional<std::int64_t> parentTaskId;
    std::int64_t projectId;
    std::string title;
    std::optional<std::string> description;
    std::string status;
    std::string type;
    std::string discipline;
    std::optional<std::string> dueAt;
    std::optional<std::string> startAt;
    std::vector<std::int64_t> assigneeIds;
    std::int64_t createdById;
    std::int64_t version;
    std::string createdAt;
    std::string updatedAt;
};

// Task fields exactly as the client sent them, before validation. The service
// layer trims, applies defaults and checks enums, producing a NewTask.
struct TaskInput
{
    std::string title;
    std::optional<std::string> description;
    std::optional<std::string> status;
    std::optional<std::string> type;
    std::optional<std::string> discipline;
    std::optional<std::string> dueAt;
    std::optional<std::string> startAt;
    std::vector<std::int64_t> assigneeIds;
    std::optional<std::int64_t> parentTaskId;
    std::optional<std::int64_t> projectId;
};

// A validated task ready to insert.
struct NewTask
{
    std::int64_t createdById;
    std::int64_t projectId;
    std::string title;
    std::optional<std::string> description;
    std::string status;
    std::string type;
    std::string discipline;
    std::optional<std::string> dueAt;
    std::optional<std::string> startAt;
    std::vector<std::int64_t> assigneeIds;
    std::optional<std::int64_t> parentTaskId;
};

// Partial update of an existing task. A disengaged outer optional means "the
// client did not send this field — leave it unchanged". For nullable columns
// the inner optional carries the new value, where nullopt means "clear it to
// NULL". This two-level shape is what lets `"description": null` erase a
// description while an absent "description" key leaves it alone.
struct TaskUpdate
{
    std::int64_t taskId{0};
    std::optional<std::string> title;
    std::optional<std::optional<std::string>> description;
    std::optional<std::string> status;
    std::optional<std::string> type;
    std::optional<std::string> discipline;
    std::optional<std::optional<std::string>> dueAt;
    std::optional<std::optional<std::string>> startAt;
    std::optional<std::vector<std::int64_t>> assigneeIds;
    std::optional<std::int64_t> projectId;

    // True when nothing was supplied, so the caller can reject a no-op edit
    // instead of bumping the version for no reason.
    bool empty() const
    {
        return !title && !description && !status && !type && !discipline &&
               !dueAt && !startAt && !assigneeIds && !projectId;
    }
};

struct TaskNoteRecord
{
    std::int64_t id;
    std::int64_t taskId;
    std::int64_t authorId;
    std::string body;
    std::string createdAt;
    std::string updatedAt;
};

// Input for adding a note to a task. authorId is set by the service from the
// authenticated user, never from the request body.
struct NewTaskNote
{
    std::int64_t taskId;
    std::int64_t authorId;
    std::string body;
};

struct CommentRecord
{
    std::int64_t id;
    std::int64_t taskId;
    std::int64_t authorId;
    std::optional<std::int64_t> parentCommentId;
    std::string body;
    std::string createdAt;
    std::string updatedAt;
};

struct NewComment
{
    std::int64_t taskId;
    std::int64_t authorId;
    std::optional<std::int64_t> parentCommentId;
    std::string body;
};

// A task together with its direct subtasks, notes, and comments, for the
// task-detail read. Subtasks are one level deep (direct children only, not
// recursive).
struct TaskDetail
{
    TaskRecord task;
    std::vector<TaskRecord> subtasks;
    std::vector<TaskNoteRecord> notes;
    std::vector<CommentRecord> comments;
};

struct NotificationRecord
{
    std::int64_t id;
    std::int64_t recipientId;
    std::int64_t actorId;
    std::int64_t taskId;
    std::string notificationType;
    std::string message;
    std::string createdAt;
    std::optional<std::string> readAt;
};

// notification_type for a blocker alert. These are the only notifications the
// client pops as a modal and the only ones replayed on reconnect, so the
// string is shared rather than written out at each site.
inline constexpr const char *kBlockerNotificationType = "blocker";

// Outcome of raising a blocker, in one transaction: the task with its new
// 'blocked' status and bumped version, plus the notification created for the
// member held responsible. The caller pushes that notification over the
// WebSocket; the stored row is what guarantees delivery if they are offline.
struct BlockerRaised
{
    TaskRecord task;
    NotificationRecord notification;
};

}  // namespace taskmanager
