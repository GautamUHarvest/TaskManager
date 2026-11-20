#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

// Tasks, their assignees (task_assignees) and their audit log (task_events).
// Every returned TaskRecord has assigneeIds filled in.
class TaskRepository
{
  public:
    explicit TaskRepository(const db::Database &database);

    // Both throw std::invalid_argument when an assignee or the parent task
    // does not exist. createSubtask also logs 'subtask_created' on the parent.
    TaskRecord create(const NewTask &task);
    TaskRecord createSubtask(const NewTask &task);

    // Sets the status, bumps the version and logs 'status_changed'.
    // Throws NotFoundError when the task does not exist.
    TaskRecord updateStatus(std::int64_t taskId,
                            const std::string &status,
                            std::int64_t actorId);
    // Applies the engaged fields of `update`, bumps the version and logs
    // 'updated'. Throws NotFoundError when the task does not exist.
    TaskRecord update(const TaskUpdate &update, std::int64_t actorId);
    // Deletes a task and the rows that reference it (notes, events,
    // notifications; assignees and comments cascade). The caller must have
    // already rejected tasks that still have subtasks — see countSubtasks.
    void remove(std::int64_t taskId);

    // Flags a task as blocked on `responsibleId` in one transaction: sets the
    // status to 'blocked', bumps the version, logs a 'blocked' event, and
    // stores the notification for the responsible member.
    BlockerRaised raiseBlocker(std::int64_t taskId,
                               std::int64_t actorId,
                               std::int64_t responsibleId,
                               const std::string &eventDetail,
                               const std::string &notificationMessage);

    std::optional<TaskRecord> find(std::int64_t id);
    std::int64_t countSubtasks(std::int64_t parentTaskId);
    // Direct children only, oldest first.
    std::vector<TaskRecord> listSubtasks(std::int64_t parentTaskId);
    // Newest first.
    std::vector<TaskRecord> listAll();
    // Tasks the user is assigned to: dated ones first by due date, then newest.
    std::vector<TaskRecord> listByAssignee(std::int64_t userId);
    // status = 'done', most recently updated first.
    std::vector<TaskRecord> listCompleted();
    // Newest first.
    std::vector<TaskRecord> listByProject(std::int64_t projectId);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
