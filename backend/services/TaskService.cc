#include "TaskService.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <stdexcept>

namespace taskmanager
{
namespace
{
constexpr std::array<const char *, 5> kTaskStatuses = {
    "todo", "in_progress", "blocked", "done", "cancelled"};

constexpr std::array<const char *, 12> kTaskTypes = {
    "design", "test", "decide", "measure", "select", "buy",
    "admin", "code", "make", "data", "doc", "integrate"};

constexpr std::array<const char *, 13> kTaskDisciplines = {
    "mechanical", "electronics", "software", "server_backend",
    "communications", "embedded", "control_systems",
    "project_management", "operations", "payments",
    "systems_integration", "frontend", "decide"};

std::string trim(const std::string &value)
{
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
    {
        return std::string();
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string resolveStatus(const std::optional<std::string> &status)
{
    if (!status)
    {
        return "todo";
    }
    const std::string value = trim(*status);
    if (std::find(kTaskStatuses.begin(), kTaskStatuses.end(), value) ==
        kTaskStatuses.end())
    {
        throw std::invalid_argument(
            "Field 'status' must be one of: todo, in_progress, blocked, done, "
            "cancelled");
    }
    return value;
}

std::optional<std::string> normalizeOptionalText(
    const std::optional<std::string> &value, std::size_t maxLength,
    const char *field)
{
    if (!value)
    {
        return std::nullopt;
    }
    const std::string trimmed = trim(*value);
    if (trimmed.empty())
    {
        return std::nullopt;
    }
    if (trimmed.size() > maxLength)
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' is too long");
    }
    return trimmed;
}

// Validates and normalizes the shared task fields into a NewTask. Used by both
// addTask (parentTaskId optional) and addSubtask (parentTaskId required, checked
// by the caller).
template <typename Container>
std::string resolveEnum(const std::optional<std::string> &value,
                        const Container &allowed, const char *field,
                        const char *defaultValue)
{
    if (!value)
    {
        return defaultValue;
    }
    const std::string trimmed = trim(*value);
    if (trimmed.empty())
    {
        return defaultValue;
    }
    if (std::find(allowed.begin(), allowed.end(), trimmed) == allowed.end())
    {
        std::string message = std::string("Field '") + field +
                              "' must be one of: ";
        for (std::size_t i = 0; i < allowed.size(); ++i)
        {
            if (i > 0)
            {
                message += ", ";
            }
            message += allowed[i];
        }
        throw std::invalid_argument(message);
    }
    return trimmed;
}

NewTask buildNewTask(std::int64_t createdById,
                     const std::string &title,
                     const std::optional<std::string> &description,
                     const std::optional<std::string> &status,
                     const std::optional<std::string> &type,
                     const std::optional<std::string> &discipline,
                     const std::optional<std::string> &dueAt,
                     const std::optional<std::string> &startAt,
                     const std::optional<std::int64_t> &assigneeId,
                     const std::optional<std::int64_t> &parentTaskId)
{
    const std::string normalizedTitle = trim(title);
    if (normalizedTitle.empty())
    {
        throw std::invalid_argument("Field 'title' is required");
    }
    if (normalizedTitle.size() > 200)
    {
        throw std::invalid_argument("Field 'title' must be 1 to 200 characters");
    }
    if (assigneeId && *assigneeId <= 0)
    {
        throw std::invalid_argument("Field 'assignee_id' must be a positive id");
    }
    if (parentTaskId && *parentTaskId <= 0)
    {
        throw std::invalid_argument(
            "Field 'parent_task_id' must be a positive id");
    }

    NewTask newTask;
    newTask.createdById = createdById;
    newTask.title = normalizedTitle;
    newTask.description = normalizeOptionalText(description, 4000, "description");
    newTask.status = resolveStatus(status);
    newTask.type = resolveEnum(type, kTaskTypes, "type", "decide");
    newTask.discipline =
        resolveEnum(discipline, kTaskDisciplines, "discipline", "decide");
    newTask.dueAt = normalizeOptionalText(dueAt, 64, "due_at");
    newTask.startAt = normalizeOptionalText(startAt, 64, "start_at");
    newTask.assigneeId = assigneeId;
    newTask.parentTaskId = parentTaskId;
    return newTask;
}
}  // namespace

TaskService::TaskService(AuthService &auth, TaskRepository &repository)
    : auth_(auth), repository_(repository)
{
}

TaskRecord TaskService::addTask(
    const std::string &accessToken,
    const std::string &title,
    const std::optional<std::string> &description,
    const std::optional<std::string> &status,
    const std::optional<std::string> &type,
    const std::optional<std::string> &discipline,
    const std::optional<std::string> &dueAt,
    const std::optional<std::string> &startAt,
    const std::optional<std::int64_t> &assigneeId,
    const std::optional<std::int64_t> &parentTaskId)
{
    const auto user = auth_.profile(accessToken);
    return repository_.createTask(buildNewTask(
        user.id, title, description, status, type, discipline, dueAt, startAt,
        assigneeId, parentTaskId));
}

TaskRecord TaskService::addSubtask(
    const std::string &accessToken,
    std::int64_t parentTaskId,
    const std::string &title,
    const std::optional<std::string> &description,
    const std::optional<std::string> &status,
    const std::optional<std::string> &type,
    const std::optional<std::string> &discipline,
    const std::optional<std::string> &dueAt,
    const std::optional<std::string> &startAt,
    const std::optional<std::int64_t> &assigneeId)
{
    const auto user = auth_.profile(accessToken);
    if (parentTaskId <= 0)
    {
        throw std::invalid_argument(
            "Field 'parent_task_id' must be a positive id");
    }
    return repository_.createSubtask(buildNewTask(
        user.id, title, description, status, type, discipline, dueAt, startAt,
        assigneeId, parentTaskId));
}

TaskNoteRecord TaskService::addNote(const std::string &accessToken,
                                    std::int64_t taskId,
                                    const std::string &body)
{
    const auto user = auth_.profile(accessToken);
    if (taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    const std::string trimmedBody = trim(body);
    if (trimmedBody.empty())
    {
        throw std::invalid_argument("Field 'body' is required");
    }
    if (trimmedBody.size() > 4000)
    {
        throw std::invalid_argument("Field 'body' is too long");
    }

    NewTaskNote note;
    note.taskId = taskId;
    note.authorId = user.id;
    note.body = trimmedBody;
    return repository_.addNote(note);
}

TaskRecord TaskService::changeStatus(const std::string &accessToken,
                                     std::int64_t taskId,
                                     const std::string &status)
{
    const auto user = auth_.profile(accessToken);
    if (taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    // status is required here; resolveStatus validates it against the allowed
    // set (it would also accept nullopt as 'todo', but the controller always
    // supplies a non-empty value).
    const std::string resolved = resolveStatus(status);
    return repository_.updateStatus(taskId, resolved, user.id);
}

TaskDetail TaskService::taskDetail(const std::string &accessToken,
                                   std::int64_t taskId)
{
    auth_.profile(accessToken);  // authenticate; throws if invalid
    if (taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    auto task = repository_.findTask(taskId);
    if (!task)
    {
        throw std::invalid_argument("Task not found");
    }

    TaskDetail detail;
    detail.task = *task;
    detail.subtasks = repository_.listSubtasks(taskId);
    detail.notes = repository_.listNotes(taskId);
    return detail;
}

std::vector<UserRecord> TaskService::allUsers(const std::string &accessToken)
{
    auth_.profile(accessToken);  // authenticate; throws if invalid
    return repository_.listUsers();
}

std::vector<NotificationRecord> TaskService::notifications(
    const std::string &accessToken)
{
    const auto user = auth_.profile(accessToken);
    return repository_.listNotifications(user.id);
}

std::vector<TaskRecord> TaskService::allTasks(const std::string &accessToken)
{
    auth_.profile(accessToken);
    return repository_.listAllTasks();
}

std::vector<TaskRecord> TaskService::myTasks(const std::string &accessToken)
{
    const auto user = auth_.profile(accessToken);
    return repository_.listTasksByAssignee(user.id);
}

std::vector<TaskRecord> TaskService::completedTasks(
    const std::string &accessToken)
{
    auth_.profile(accessToken);
    return repository_.listCompletedTasks();
}

}  // namespace taskmanager
