#include "TaskService.h"

#include "../common/Errors.h"
#include "TaskRules.h"

#include <stdexcept>
#include <utility>

namespace taskmanager
{

TaskService::TaskService(TaskRepository &tasks,
                         ProjectRepository &projects,
                         UserRepository &users,
                         NoteRepository &notes,
                         CommentRepository &comments)
    : tasks_(tasks),
      projects_(projects),
      users_(users),
      notes_(notes),
      comments_(comments)
{
}

TaskRecord TaskService::requireTask(std::int64_t taskId)
{
    auto task = tasks_.find(taskId);
    if (!task)
    {
        throw NotFoundError("Task not found");
    }
    return std::move(*task);
}

void TaskService::requireProject(std::int64_t projectId)
{
    if (!projects_.find(projectId))
    {
        throw std::invalid_argument(
            "Field 'project_id' must reference an existing project");
    }
}

TaskRecord TaskService::addTask(const UserRecord &actor, const TaskInput &input)
{
    const auto task = rules::buildNewTask(actor.id, input);
    // The default project always exists, so only a supplied id is looked up.
    if (input.projectId)
    {
        requireProject(task.projectId);
    }
    return tasks_.create(task);
}

TaskRecord TaskService::addSubtask(const UserRecord &actor,
                                   std::int64_t parentTaskId,
                                   TaskInput input)
{
    rules::requirePositiveId(parentTaskId, "parent_task_id");
    input.parentTaskId = parentTaskId;
    const auto task = rules::buildNewTask(actor.id, input);
    if (input.projectId)
    {
        requireProject(task.projectId);
    }
    return tasks_.createSubtask(task);
}

TaskRecord TaskService::changeStatus(const UserRecord &actor,
                                     std::int64_t taskId,
                                     const std::string &status)
{
    rules::requirePositiveId(taskId, "task_id");
    return tasks_.updateStatus(taskId, rules::resolveStatus(status), actor.id);
}

TaskRecord TaskService::editTask(const UserRecord &actor, TaskUpdate update)
{
    rules::requirePositiveId(update.taskId, "task_id");
    if (update.empty())
    {
        throw std::invalid_argument("Supply at least one field to update");
    }
    const auto task = requireTask(update.taskId);
    // Reassigning is open to every member; any other change still needs the
    // creator or an assignee.
    const bool allowed = update.onlyAssignees()
                             ? rules::canAssignTask(task, actor.id)
                             : rules::canEditTask(task, actor.id);
    if (!allowed)
    {
        throw ForbiddenError(
            "Only the task's creator or an assignee can edit it");
    }

    auto normalized = rules::normalizeTaskUpdate(std::move(update));
    if (normalized.projectId)
    {
        requireProject(*normalized.projectId);
    }
    return tasks_.update(normalized, actor.id);
}

void TaskService::deleteTask(const UserRecord &actor, std::int64_t taskId)
{
    rules::requirePositiveId(taskId, "task_id");
    if (!rules::canDeleteTask(requireTask(taskId), actor.id))
    {
        throw ForbiddenError("Only the task's creator can delete it");
    }
    // Deleting a parent would orphan its children, and the parent_task_id
    // foreign key is ON DELETE RESTRICT anyway. Refuse early with a message
    // that says how many are in the way.
    const auto subtasks = tasks_.countSubtasks(taskId);
    if (subtasks > 0)
    {
        throw std::invalid_argument(
            "Cannot delete a task that still has " + std::to_string(subtasks) +
            (subtasks == 1 ? " subtask. Delete it first."
                           : " subtasks. Delete them first."));
    }
    tasks_.remove(taskId);
}

BlockerRaised TaskService::raiseBlocker(const UserRecord &actor,
                                        std::int64_t taskId,
                                        std::int64_t responsibleId,
                                        const std::string &message)
{
    rules::requirePositiveId(taskId, "task_id");
    rules::requirePositiveId(responsibleId, "responsible_user_id");
    if (responsibleId == actor.id)
    {
        throw std::invalid_argument("You cannot flag yourself as the blocker");
    }
    const std::string trimmedMessage = rules::normalizeBody(message);

    const auto task = requireTask(taskId);
    if (!rules::canEditTask(task, actor.id))
    {
        throw ForbiddenError(
            "Only the task's creator or an assignee can raise a blocker");
    }
    // The notifications foreign key would catch a bad id, but only as an
    // opaque constraint failure — check it here so the message names the
    // field.
    if (!users_.findActive(responsibleId))
    {
        throw std::invalid_argument(
            "Field 'responsible_user_id' must reference an active user");
    }

    const std::string notificationMessage =
        actor.displayName + " flagged you as blocking \"" + task.title +
        "\": " + trimmedMessage;
    return tasks_.raiseBlocker(
        taskId, actor.id, responsibleId, trimmedMessage, notificationMessage);
}

TaskDetail TaskService::taskDetail(std::int64_t taskId)
{
    rules::requirePositiveId(taskId, "task_id");
    TaskDetail detail;
    detail.task = requireTask(taskId);
    detail.subtasks = tasks_.listSubtasks(taskId);
    detail.notes = notes_.listForTask(taskId);
    detail.comments = comments_.listForTask(taskId);
    return detail;
}

std::vector<TaskRecord> TaskService::allTasks()
{
    return tasks_.listAll();
}

std::vector<TaskRecord> TaskService::myTasks(const UserRecord &actor)
{
    return tasks_.listByAssignee(actor.id);
}

std::vector<TaskRecord> TaskService::completedTasks()
{
    return tasks_.listCompleted();
}

std::vector<TaskRecord> TaskService::projectTasks(std::int64_t projectId)
{
    rules::requirePositiveId(projectId, "project_id");
    requireProject(projectId);
    return tasks_.listByProject(projectId);
}

}  // namespace taskmanager
