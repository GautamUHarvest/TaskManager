#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

struct TaskRecord
{
    std::int64_t id;
    std::optional<std::int64_t> parentTaskId;
    std::string title;
    std::optional<std::string> description;
    std::string status;
    std::string type;
    std::string discipline;
    std::optional<std::string> dueAt;
    std::optional<std::string> startAt;
    std::optional<std::int64_t> assigneeId;
    std::int64_t createdById;
    std::int64_t version;
    std::string createdAt;
    std::string updatedAt;
};

// Input for creating a task. createdById is set by the service from the
// authenticated user, never from the request body.
struct NewTask
{
    std::int64_t createdById;
    std::string title;
    std::optional<std::string> description;
    std::string status;
    std::string type;
    std::string discipline;
    std::optional<std::string> dueAt;
    std::optional<std::string> startAt;
    std::optional<std::int64_t> assigneeId;
    std::optional<std::int64_t> parentTaskId;
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

// A task together with its direct subtasks and its notes, for the task-detail
// read. Subtasks are one level deep (direct children only, not recursive).
struct TaskDetail
{
    TaskRecord task;
    std::vector<TaskRecord> subtasks;
    std::vector<TaskNoteRecord> notes;
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

}  // namespace taskmanager
