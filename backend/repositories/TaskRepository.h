#pragma once

#include "../models/Task.h"
#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

class TaskRepository
{
  public:
    explicit TaskRepository(std::string databasePath);

    // --- Projects ---
    ProjectRecord createProject(const NewProject &project);
    std::vector<ProjectRecord> listProjects();
    std::optional<ProjectRecord> findProject(std::int64_t id);

    // --- Tasks ---
    TaskRecord createTask(const NewTask &task);
    TaskRecord createSubtask(const NewTask &task);
    TaskNoteRecord addNote(const NewTaskNote &note);
    TaskRecord updateStatus(std::int64_t taskId,
                            const std::string &status,
                            std::int64_t actorId);
    std::optional<TaskRecord> findTask(std::int64_t id);
    std::vector<TaskRecord> listSubtasks(std::int64_t parentTaskId);
    std::vector<TaskNoteRecord> listNotes(std::int64_t taskId);
    std::vector<UserRecord> listUsers();
    std::vector<NotificationRecord> listNotifications(std::int64_t recipientId);
    std::vector<TaskRecord> listAllTasks();
    std::vector<TaskRecord> listTasksByAssignee(std::int64_t assigneeId);
    std::vector<TaskRecord> listCompletedTasks();
    std::vector<TaskRecord> listTasksByProject(std::int64_t projectId);

    // --- Comments (threaded) ---
    CommentRecord addComment(const NewComment &comment);
    std::vector<CommentRecord> listComments(std::int64_t taskId);
    std::optional<CommentRecord> findComment(std::int64_t id);

    // --- Notifications ---
    void createNotification(std::int64_t recipientId,
                            std::int64_t actorId,
                            std::int64_t taskId,
                            const std::string &type,
                            const std::string &message);

    // Returns the user ids assigned to a task.
    std::vector<std::int64_t> listAssigneeIds(std::int64_t taskId);

  private:
    std::string databasePath_;
};

}  // namespace taskmanager
