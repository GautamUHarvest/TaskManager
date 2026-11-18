#pragma once

#include "../models/Task.h"
#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

// Read-only access to the task-management domain (users, tasks,
// notifications). Mirrors AuthRepository's raw-SQLite style; this is
// intentionally un-abstracted for now and will be refactored later alongside
// the rest of the data layer.
class TaskRepository
{
  public:
    explicit TaskRepository(std::string databasePath);

    TaskRecord createTask(const NewTask &task);
    // Creates a child task (parent_task_id required) and records a
    // 'subtask_created' event on the parent, atomically.
    TaskRecord createSubtask(const NewTask &task);
    // Adds a note to an existing task. Throws std::invalid_argument if the task
    // does not exist (FK constraint).
    TaskNoteRecord addNote(const NewTaskNote &note);
    // Changes a task's status, bumping version and updated_at, and records a
    // 'status_changed' event, atomically. Throws std::invalid_argument if the
    // task does not exist.
    TaskRecord updateStatus(std::int64_t taskId,
                            const std::string &status,
                            std::int64_t actorId);
    // Returns a single task by id, or nullopt if it does not exist.
    std::optional<TaskRecord> findTask(std::int64_t id);
    // Direct subtasks (parent_task_id = id), oldest first.
    std::vector<TaskRecord> listSubtasks(std::int64_t parentTaskId);
    // Notes attached to a task, oldest first.
    std::vector<TaskNoteRecord> listNotes(std::int64_t taskId);
    std::vector<UserRecord> listUsers();
    std::vector<NotificationRecord> listNotifications(std::int64_t recipientId);
    std::vector<TaskRecord> listAllTasks();
    std::vector<TaskRecord> listTasksByAssignee(std::int64_t assigneeId);
    std::vector<TaskRecord> listCompletedTasks();

  private:
    std::string databasePath_;
};

}  // namespace taskmanager
