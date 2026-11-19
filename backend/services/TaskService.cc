#include "TaskService.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <stdexcept>
#include <utility>

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

// Default project when the client does not specify one. Matches the
// "Unidentified" project seeded in migration 004.
constexpr std::int64_t kDefaultProjectId = 1;

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
        if (std::find(unique.begin(), unique.end(), id) == unique.end())
        {
            unique.push_back(id);
        }
    }
    return unique;
}

// Shared body rule for notes and comments: non-empty after trimming, at most
// 4000 characters. The SQLite CHECK on task_notes.body / comments.body
// enforces non-emptiness too; this gives a readable 400 instead.
std::string normalizeBody(const std::string &body)
{
    const std::string trimmed = trim(body);
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

// Applies the same field rules as buildNewTask, but only to the fields the
// client actually supplied. Fields left disengaged stay untouched.
TaskUpdate normalizeTaskUpdate(TaskUpdate update)
{
    if (update.title)
    {
        const std::string trimmed = trim(*update.title);
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
        update.type = resolveEnum(update.type, kTaskTypes, "type", "decide");
    }
    if (update.discipline)
    {
        update.discipline = resolveEnum(
            update.discipline, kTaskDisciplines, "discipline", "decide");
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
    if (update.projectId && *update.projectId <= 0)
    {
        throw std::invalid_argument("Field 'project_id' must be a positive id");
    }
    return update;
}

NewTask buildNewTask(std::int64_t createdById,
                     const std::string &title,
                     const std::optional<std::string> &description,
                     const std::optional<std::string> &status,
                     const std::optional<std::string> &type,
                     const std::optional<std::string> &discipline,
                     const std::optional<std::string> &dueAt,
                     const std::optional<std::string> &startAt,
                     const std::vector<std::int64_t> &assigneeIds,
                     const std::optional<std::int64_t> &parentTaskId,
                     const std::optional<std::int64_t> &projectId)
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
    if (parentTaskId && *parentTaskId <= 0)
    {
        throw std::invalid_argument(
            "Field 'parent_task_id' must be a positive id");
    }
    if (projectId && *projectId <= 0)
    {
        throw std::invalid_argument("Field 'project_id' must be a positive id");
    }

    NewTask newTask;
    newTask.createdById = createdById;
    newTask.projectId = projectId.value_or(kDefaultProjectId);
    newTask.title = normalizedTitle;
    newTask.description = normalizeOptionalText(description, 4000, "description");
    newTask.status = resolveStatus(status);
    newTask.type = resolveEnum(type, kTaskTypes, "type", "decide");
    newTask.discipline =
        resolveEnum(discipline, kTaskDisciplines, "discipline", "decide");
    newTask.dueAt = normalizeOptionalText(dueAt, 64, "due_at");
    newTask.startAt = normalizeOptionalText(startAt, 64, "start_at");
    newTask.assigneeIds = normalizeAssigneeIds(assigneeIds);
    newTask.parentTaskId = parentTaskId;
    return newTask;
}
}  // namespace

TaskService::TaskService(AuthService &auth, TaskRepository &repository)
    : auth_(auth), repository_(repository)
{
}

ProjectRecord TaskService::addProject(
    const std::string &accessToken,
    const std::string &name,
    const std::optional<std::string> &description)
{
    const auto user = auth_.profile(accessToken);
    const std::string trimmedName = trim(name);
    if (trimmedName.empty())
    {
        throw std::invalid_argument("Field 'name' is required");
    }
    if (trimmedName.size() > 120)
    {
        throw std::invalid_argument("Field 'name' must be 1 to 120 characters");
    }

    NewProject project;
    project.createdById = user.id;
    project.name = trimmedName;
    project.description =
        normalizeOptionalText(description, 4000, "description");
    return repository_.createProject(project);
}

std::vector<ProjectRecord> TaskService::allProjects(
    const std::string &accessToken)
{
    auth_.profile(accessToken);  // authenticate; throws if invalid
    return repository_.listProjects();
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
    const std::vector<std::int64_t> &assigneeIds,
    const std::optional<std::int64_t> &parentTaskId,
    const std::optional<std::int64_t> &projectId)
{
    const auto user = auth_.profile(accessToken);
    auto newTask = buildNewTask(user.id, title, description, status, type,
                                discipline, dueAt, startAt, assigneeIds,
                                parentTaskId, projectId);
    // project_id has no DB-level foreign key (see migration 006), so verify the
    // project exists here when the client supplied one. The default project
    // (id 1) always exists, so an omitted project_id needs no lookup.
    if (projectId && !repository_.findProject(newTask.projectId))
    {
        throw std::invalid_argument(
            "Field 'project_id' must reference an existing project");
    }
    return repository_.createTask(newTask);
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
    const std::vector<std::int64_t> &assigneeIds,
    const std::optional<std::int64_t> &projectId)
{
    const auto user = auth_.profile(accessToken);
    if (parentTaskId <= 0)
    {
        throw std::invalid_argument(
            "Field 'parent_task_id' must be a positive id");
    }
    auto newTask = buildNewTask(user.id, title, description, status, type,
                                discipline, dueAt, startAt, assigneeIds,
                                parentTaskId, projectId);
    // See addTask: project_id existence is enforced in the service layer.
    if (projectId && !repository_.findProject(newTask.projectId))
    {
        throw std::invalid_argument(
            "Field 'project_id' must reference an existing project");
    }
    return repository_.createSubtask(newTask);
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

CommentRecord TaskService::addComment(
    const std::string &accessToken,
    std::int64_t taskId,
    const std::string &body,
    const std::optional<std::int64_t> &parentCommentId)
{
    const auto user = auth_.profile(accessToken);
    if (taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    if (parentCommentId && *parentCommentId <= 0)
    {
        throw std::invalid_argument(
            "Field 'parent_comment_id' must be a positive id");
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

    const auto task = repository_.findTask(taskId);
    if (!task)
    {
        throw std::invalid_argument("Task not found");
    }

    // For a reply, the parent comment must exist and belong to the same task.
    // Capture its author so they can be notified alongside the assignees.
    std::optional<std::int64_t> parentAuthorId;
    if (parentCommentId)
    {
        const auto parent = repository_.findComment(*parentCommentId);
        if (!parent || parent->taskId != taskId)
        {
            throw std::invalid_argument(
                "Field 'parent_comment_id' must reference a comment on this "
                "task");
        }
        parentAuthorId = parent->authorId;
    }

    NewComment comment;
    comment.taskId = taskId;
    comment.authorId = user.id;
    comment.parentCommentId = parentCommentId;
    comment.body = trimmedBody;
    const auto created = repository_.addComment(comment);

    // Notify every assignee of the task, plus (on a reply) the author of the
    // parent comment even if they are not assigned. The comment's own author is
    // never notified, and each recipient is notified at most once.
    const std::string message =
        user.displayName + " commented on \"" + task->title + "\"";
    std::vector<std::int64_t> notified;
    const auto notify = [&](std::int64_t recipientId) {
        if (recipientId == user.id)
        {
            return;
        }
        if (std::find(notified.begin(), notified.end(), recipientId) !=
            notified.end())
        {
            return;
        }
        notified.push_back(recipientId);
        repository_.createNotification(
            recipientId, user.id, taskId, "comment", message);
    };
    for (const auto assigneeId : task->assigneeIds)
    {
        notify(assigneeId);
    }
    if (parentAuthorId)
    {
        notify(*parentAuthorId);
    }

    return created;
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

TaskRecord TaskService::editTask(const std::string &accessToken,
                                 TaskUpdate update)
{
    const auto user = auth_.profile(accessToken);
    if (update.taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    if (update.empty())
    {
        throw std::invalid_argument(
            "Supply at least one field to update");
    }

    const auto task = repository_.findTask(update.taskId);
    if (!task)
    {
        throw std::invalid_argument("Task not found");
    }
    const bool isCreator = task->createdById == user.id;
    const bool isAssignee = std::find(task->assigneeIds.begin(),
                                      task->assigneeIds.end(),
                                      user.id) != task->assigneeIds.end();
    if (!isCreator && !isAssignee)
    {
        throw ForbiddenError(
            "Only the task's creator or an assignee can edit it");
    }

    auto normalized = normalizeTaskUpdate(std::move(update));
    // project_id has no DB-level foreign key (migration 006), so its existence
    // is checked here, exactly as addTask does.
    if (normalized.projectId &&
        !repository_.findProject(*normalized.projectId))
    {
        throw std::invalid_argument(
            "Field 'project_id' must reference an existing project");
    }
    return repository_.updateTask(normalized, user.id);
}

void TaskService::deleteTask(const std::string &accessToken,
                             std::int64_t taskId)
{
    const auto user = auth_.profile(accessToken);
    if (taskId <= 0)
    {
        throw std::invalid_argument("Field 'task_id' must be a positive id");
    }
    const auto task = repository_.findTask(taskId);
    if (!task)
    {
        throw std::invalid_argument("Task not found");
    }
    if (task->createdById != user.id)
    {
        throw ForbiddenError("Only the task's creator can delete it");
    }
    // Deleting a parent would orphan its children, and the tasks
    // parent_task_id foreign key is ON DELETE RESTRICT anyway. Refuse early
    // with a message that says how many are in the way.
    const auto subtasks = repository_.countSubtasks(taskId);
    if (subtasks > 0)
    {
        throw std::invalid_argument(
            "Cannot delete a task that still has " + std::to_string(subtasks) +
            (subtasks == 1 ? " subtask. Delete it first."
                           : " subtasks. Delete them first."));
    }
    repository_.deleteTask(taskId);
}

TaskNoteRecord TaskService::editNote(const std::string &accessToken,
                                     std::int64_t noteId,
                                     const std::string &body)
{
    const auto user = auth_.profile(accessToken);
    if (noteId <= 0)
    {
        throw std::invalid_argument("Field 'note_id' must be a positive id");
    }
    const auto note = repository_.findNote(noteId);
    if (!note)
    {
        throw std::invalid_argument("Note not found");
    }
    if (note->authorId != user.id)
    {
        throw ForbiddenError("Only the note's author can edit it");
    }
    return repository_.updateNote(noteId, normalizeBody(body));
}

void TaskService::deleteNote(const std::string &accessToken,
                             std::int64_t noteId)
{
    const auto user = auth_.profile(accessToken);
    if (noteId <= 0)
    {
        throw std::invalid_argument("Field 'note_id' must be a positive id");
    }
    const auto note = repository_.findNote(noteId);
    if (!note)
    {
        throw std::invalid_argument("Note not found");
    }
    if (note->authorId != user.id)
    {
        throw ForbiddenError("Only the note's author can delete it");
    }
    repository_.deleteNote(noteId);
}

CommentRecord TaskService::editComment(const std::string &accessToken,
                                       std::int64_t commentId,
                                       const std::string &body)
{
    const auto user = auth_.profile(accessToken);
    if (commentId <= 0)
    {
        throw std::invalid_argument("Field 'comment_id' must be a positive id");
    }
    const auto comment = repository_.findComment(commentId);
    if (!comment)
    {
        throw std::invalid_argument("Comment not found");
    }
    if (comment->authorId != user.id)
    {
        throw ForbiddenError("Only the comment's author can edit it");
    }
    return repository_.updateComment(commentId, normalizeBody(body));
}

std::int64_t TaskService::deleteComment(const std::string &accessToken,
                                        std::int64_t commentId)
{
    const auto user = auth_.profile(accessToken);
    if (commentId <= 0)
    {
        throw std::invalid_argument("Field 'comment_id' must be a positive id");
    }
    const auto comment = repository_.findComment(commentId);
    if (!comment)
    {
        throw std::invalid_argument("Comment not found");
    }
    if (comment->authorId != user.id)
    {
        throw ForbiddenError("Only the comment's author can delete it");
    }
    // Replies cascade (comments.parent_comment_id ON DELETE CASCADE), so count
    // them before the delete to report what went with it.
    const auto replies = repository_.countCommentDescendants(commentId);
    repository_.deleteComment(commentId);
    return replies;
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
    detail.comments = repository_.listComments(taskId);
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
