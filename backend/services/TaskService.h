#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/TaskRepository.h"
#include "AuthService.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

// Task-management reads. Every call authenticates the bearer access token
// through AuthService (reusing the existing JWT verification) and throws
// UnauthorizedError on an invalid or expired token.
class TaskService
{
  public:
    TaskService(AuthService &auth, TaskRepository &repository);

    TaskRecord addTask(const std::string &accessToken,
                       const std::string &title,
                       const std::optional<std::string> &description,
                       const std::optional<std::string> &status,
                       const std::optional<std::string> &type,
                       const std::optional<std::string> &discipline,
                       const std::optional<std::string> &dueAt,
                       const std::optional<std::string> &startAt,
                       const std::optional<std::int64_t> &assigneeId,
                       const std::optional<std::int64_t> &parentTaskId);
    // Creates a subtask under an existing parent task. parent_task_id is
    // required (unlike addTask, where it is optional).
    TaskRecord addSubtask(const std::string &accessToken,
                          std::int64_t parentTaskId,
                          const std::string &title,
                          const std::optional<std::string> &description,
                          const std::optional<std::string> &status,
                          const std::optional<std::string> &type,
                          const std::optional<std::string> &discipline,
                          const std::optional<std::string> &dueAt,
                          const std::optional<std::string> &startAt,
                          const std::optional<std::int64_t> &assigneeId);
    // Adds a free-text note to an existing task, authored by the token's user.
    TaskNoteRecord addNote(const std::string &accessToken,
                           std::int64_t taskId,
                           const std::string &body);
    // Changes an existing task's status to one of the allowed values.
    TaskRecord changeStatus(const std::string &accessToken,
                            std::int64_t taskId,
                            const std::string &status);
    // Returns a task with its direct subtasks and notes. Throws
    // std::invalid_argument ("Task not found") if the id does not exist.
    TaskDetail taskDetail(const std::string &accessToken, std::int64_t taskId);
    std::vector<UserRecord> allUsers(const std::string &accessToken);
    std::vector<NotificationRecord> notifications(
        const std::string &accessToken);
    std::vector<TaskRecord> allTasks(const std::string &accessToken);
    std::vector<TaskRecord> myTasks(const std::string &accessToken);
    std::vector<TaskRecord> completedTasks(const std::string &accessToken);

  private:
    AuthService &auth_;
    TaskRepository &repository_;
};

}  // namespace taskmanager
