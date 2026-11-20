#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/CommentRepository.h"
#include "../repositories/NoteRepository.h"
#include "../repositories/ProjectRepository.h"
#include "../repositories/TaskRepository.h"
#include "../repositories/UserRepository.h"

#include <cstdint>
#include <string>
#include <vector>

namespace taskmanager
{

// Task lifecycle: create, edit, status, delete, blockers, and the task reads.
//
// Every method takes the already-authenticated caller (`actor`); verifying
// the bearer token is the controller's job. Permission model (see
// apirequirement.md §4 and rules::canEditTask): a task may be edited, or have
// a blocker raised on it, by its creator or any assignee, and deleted only by
// its creator. Violations throw ForbiddenError (HTTP 403).
class TaskService
{
  public:
    TaskService(TaskRepository &tasks,
                ProjectRepository &projects,
                UserRepository &users,
                NoteRepository &notes,
                CommentRepository &comments);

    // parent_task_id and project_id are optional; an omitted project_id means
    // the default "Unidentified" project.
    TaskRecord addTask(const UserRecord &actor, const TaskInput &input);
    // Creates a subtask under an existing parent; input.parentTaskId is
    // ignored in favour of parentTaskId.
    TaskRecord addSubtask(const UserRecord &actor,
                          std::int64_t parentTaskId,
                          TaskInput input);
    TaskRecord changeStatus(const UserRecord &actor,
                            std::int64_t taskId,
                            const std::string &status);
    // Applies the engaged fields of `update`. Throws std::invalid_argument
    // when nothing was supplied.
    TaskRecord editTask(const UserRecord &actor, TaskUpdate update);
    // Refuses while the task still has subtasks — those go first.
    void deleteTask(const UserRecord &actor, std::int64_t taskId);

    // Flags the task as blocked on `responsibleId` (who may not be the
    // caller) and stores an alert for them. The caller pushes the returned
    // notification over the WebSocket.
    BlockerRaised raiseBlocker(const UserRecord &actor,
                               std::int64_t taskId,
                               std::int64_t responsibleId,
                               const std::string &message);

    // A task with its direct subtasks, notes, and comments.
    TaskDetail taskDetail(std::int64_t taskId);
    std::vector<TaskRecord> allTasks();
    std::vector<TaskRecord> myTasks(const UserRecord &actor);
    std::vector<TaskRecord> completedTasks();

  private:
    // The task, or NotFoundError ("Task not found").
    TaskRecord requireTask(std::int64_t taskId);
    // project_id has no DB-level foreign key (migration 006), so a supplied
    // project id is checked here.
    void requireProject(std::int64_t projectId);

    TaskRepository &tasks_;
    ProjectRepository &projects_;
    UserRepository &users_;
    NoteRepository &notes_;
    CommentRepository &comments_;
};

}  // namespace taskmanager
