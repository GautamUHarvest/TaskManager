#include "TaskRules.h"

#include "../common/Text.h"

#include <algorithm>
#include <array>
#include <stdexcept>
#include <utility>

namespace taskmanager::rules
{
namespace
{
constexpr std::array<const char *, 5> kTaskStatuses = {
    "todo", "in_progress", "blocked", "done", "cancelled"};

// Keep in sync with the CHECK in migrations/007_task_type_plan_review.sql.
constexpr std::array<const char *, 14> kTaskTypes = {
    "design", "test", "decide", "measure", "select", "buy",
    "admin", "code", "make", "data", "doc", "integrate",
    "plan", "review"};

constexpr std::array<const char *, 13> kTaskDisciplines = {
    "mechanical", "electronics", "software", "server_backend",
    "communications", "embedded", "control_systems",
    "project_management", "operations", "payments",
    "systems_integration", "frontend", "decide"};

template <typename Container, typename Value>
bool contains(const Container &items, const Value &value)
{
    return std::find(items.begin(), items.end(), value) != items.end();
}

template <typename Container>
std::string resolveEnum(const std::optional<std::string> &value,
                        const Container &allowed,
                        const char *field,
                        const char *defaultValue)
{
    if (!value)
    {
        return defaultValue;
    }
    const std::string trimmed = text::trim(*value);
    if (trimmed.empty())
    {
        return defaultValue;
    }
    if (!contains(allowed, trimmed))
    {
        std::string message =
            std::string("Field '") + field + "' must be one of: ";
        for (std::size_t i = 0; i < allowed.size(); ++i)
        {
            message += (i > 0 ? ", " : "");
            message += allowed[i];
        }
        throw std::invalid_argument(message);
    }
    return trimmed;
}

// Marks a nullable-column value as "the client sent this field", where the
// inner optional carries the new value (nullopt meaning SQL NULL). Built with
// in_place so it cannot be mistaken for optional's converting assignment,
// which behaves subtly when T is itself an optional.
std::optional<std::optional<std::string>> fieldPresent(
    std::optional<std::string> value)
{
    return std::optional<std::optional<std::string>>(std::in_place,
                                                     std::move(value));
}

bool isAssignee(const TaskRecord &task, std::int64_t userId)
{
    return std::find(task.assigneeIds.begin(), task.assigneeIds.end(),
                     userId) != task.assigneeIds.end();
}
}  // namespace

std::string resolveStatus(const std::optional<std::string> &status)
{
    if (!status)
    {
        return "todo";
    }
    // Unlike type/discipline, a blank status is an error, not the default.
    const std::string value = text::trim(*status);
    if (!contains(kTaskStatuses, value))
    {
        throw std::invalid_argument(
            "Field 'status' must be one of: todo, in_progress, blocked, done, "
            "cancelled");
    }
    return value;
}

std::string resolveType(const std::optional<std::string> &type)
{
    return resolveEnum(type, kTaskTypes, "type", "decide");
}

std::string resolveDiscipline(const std::optional<std::string> &discipline)
{
    return resolveEnum(discipline, kTaskDisciplines, "discipline", "decide");
}

std::optional<std::string> normalizeOptionalText(
    const std::optional<std::string> &value,
    std::size_t maxLength,
    const char *field)
{
    if (!value)
    {
        return std::nullopt;
    }
    const std::string trimmed = text::trim(*value);
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

std::vector<std::int64_t> normalizeAssigneeIds(
    const std::vector<std::int64_t> &assigneeIds)
{
    std::vector<std::int64_t> unique;
    for (const auto id : assigneeIds)
    {
        if (id <= 0)
        {
            throw std::invalid_argument(
                "Field 'assignee_ids' must contain positive ids");
        }
        if (!contains(unique, id))
        {
            unique.push_back(id);
        }
    }
    return unique;
}

std::string normalizeBody(const std::string &body)
{
    // The SQLite CHECK on the body columns enforces non-emptiness too; this
    // gives a readable 400 instead of a constraint failure.
    const std::string trimmed = text::trim(body);
    if (trimmed.empty())
    {
        throw std::invalid_argument("Field 'body' is required");
    }
    if (trimmed.size() > 4000)
    {
        throw std::invalid_argument("Field 'body' is too long");
    }
    return trimmed;
}

void requirePositiveId(std::int64_t id, const char *field)
{
    if (id <= 0)
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be a positive id");
    }
}

void requireValidTaskIndex(std::int64_t index)
{
    if (index < 1 || index > kMaxTaskIndex)
    {
        throw std::invalid_argument("Field 'index' must be a whole number from 1 to " +
                                    std::to_string(kMaxTaskIndex));
    }
}

NewTask buildNewTask(std::int64_t createdById, const TaskInput &input)
{
    const std::string title = text::trim(input.title);
    if (title.empty())
    {
        throw std::invalid_argument("Field 'title' is required");
    }
    if (title.size() > 200)
    {
        throw std::invalid_argument("Field 'title' must be 1 to 200 characters");
    }
    if (input.parentTaskId)
    {
        requirePositiveId(*input.parentTaskId, "parent_task_id");
    }
    if (input.projectId)
    {
        requirePositiveId(*input.projectId, "project_id");
    }
    if (input.taskIndex)
    {
        requireValidTaskIndex(*input.taskIndex);
    }

    NewTask task;
    task.createdById = createdById;
    task.projectId = input.projectId.value_or(kDefaultProjectId);
    task.title = title;
    task.description =
        normalizeOptionalText(input.description, 4000, "description");
    task.status = resolveStatus(input.status);
    task.type = resolveType(input.type);
    task.discipline = resolveDiscipline(input.discipline);
    task.dueAt = normalizeOptionalText(input.dueAt, 64, "due_at");
    task.startAt = normalizeOptionalText(input.startAt, 64, "start_at");
    task.assigneeIds = normalizeAssigneeIds(input.assigneeIds);
    task.parentTaskId = input.parentTaskId;
    task.taskIndex = input.taskIndex;
    return task;
}

TaskUpdate normalizeTaskUpdate(TaskUpdate update)
{
    if (update.title)
    {
        const std::string trimmed = text::trim(*update.title);
        if (trimmed.empty())
        {
            throw std::invalid_argument("Field 'title' must not be empty");
        }
        if (trimmed.size() > 200)
        {
            throw std::invalid_argument(
                "Field 'title' must be 1 to 200 characters");
        }
        update.title = trimmed;
    }
    if (update.description)
    {
        update.description = fieldPresent(
            normalizeOptionalText(*update.description, 4000, "description"));
    }
    if (update.status)
    {
        update.status = resolveStatus(update.status);
    }
    if (update.type)
    {
        update.type = resolveType(update.type);
    }
    if (update.discipline)
    {
        update.discipline = resolveDiscipline(update.discipline);
    }
    if (update.dueAt)
    {
        update.dueAt =
            fieldPresent(normalizeOptionalText(*update.dueAt, 64, "due_at"));
    }
    if (update.startAt)
    {
        update.startAt = fieldPresent(
            normalizeOptionalText(*update.startAt, 64, "start_at"));
    }
    if (update.assigneeIds)
    {
        update.assigneeIds = normalizeAssigneeIds(*update.assigneeIds);
    }
    if (update.projectId)
    {
        requirePositiveId(*update.projectId, "project_id");
    }
    if (update.taskIndex)
    {
        requireValidTaskIndex(*update.taskIndex);
    }
    return update;
}

bool canEditTask(const TaskRecord &task, std::int64_t userId)
{
    return task.createdById == userId || isAssignee(task, userId);
}

bool canDeleteTask(const TaskRecord &task, std::int64_t userId)
{
    return task.createdById == userId;
}

}  // namespace taskmanager::rules
