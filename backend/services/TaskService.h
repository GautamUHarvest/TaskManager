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

    // Projects. project_id is optional on task creation; when omitted the task
    // falls under the default "Unidentified" project (id 1).
    ProjectRecord addProject(const std::string &accessToken,
                             const std::string &name,
                             const std::optional<std::string> &description);
    std::vector<ProjectRecord> allProjects(const std::string &accessToken);

    TaskRecord addTask(const std::string &accessToken,
                       const std::string &title,
                       const std::optional<std::string> &description,
                       const std::optional<std::string> &status,
                       const std::optional<std::string> &type,
                       const std::optional<std::string> &discipline,
                       const std::optional<std::string> &dueAt,
                       const std::optional<std::string> &startAt,
                       const std::vector<std::int64_t> &assigneeIds,
                       const std::optional<std::int64_t> &parentTaskId,
                       const std::optional<std::int64_t> &projectId);
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
                          const std::vector<std::int64_t> &assigneeIds,
                          const std::optional<std::int64_t> &projectId);
    // Adds a free-text note to an existing task, authored by the token's user.
    TaskNoteRecord addNote(const std::string &accessToken,
                           std::int64_t taskId,
                           const std::string &body);
    // Adds a comment (or a threaded reply when parentCommentId is set) to a
    // task, and notifies every assignee of that task except the author.
    CommentRecord addComment(const std::string &accessToken,
                             std::int64_t taskId,
                             const std::string &body,
                             const std::optional<std::int64_t> &parentCommentId);
    // Changes an existing task's status to one of the allowed values.
    TaskRecord changeStatus(const std::string &accessToken,
                            std::int64_t taskId,
                            const std::string &status);

    // --- Edit / delete -----------------------------------------------------
    // Permission model (see apirequirement.md §4): a task may be edited by its
    // creator or any of its assignees, but deleted only by its creator; a note
    // or comment may be edited and deleted only by its author. A caller who is
    // authenticated but not permitted gets ForbiddenError (HTTP 403).

    // Applies the engaged fields of `update` (taskId is taken from it) and
    // returns the task with a bumped version. Throws std::invalid_argument
    // when nothing was supplied or the task does not exist.
    TaskRecord editTask(const std::string &accessToken, TaskUpdate update);
    // Deletes a task along with its notes, events, notifications, assignees
    // and comments. Refuses with std::invalid_argument when the task still has
    // subtasks — those must be dealt with first.
    void deleteTask(const std::string &accessToken, std::int64_t taskId);

    TaskNoteRecord editNote(const std::string &accessToken,
                            std::int64_t noteId,
                            const std::string &body);
    void deleteNote(const std::string &accessToken, std::int64_t noteId);

    CommentRecord editComment(const std::string &accessToken,
                              std::int64_t commentId,
                              const std::string &body);
    // Returns how many nested replies were cascade-deleted along with it, so
    // the caller can report it.
    std::int64_t deleteComment(const std::string &accessToken,
                               std::int64_t commentId);
    // Returns a task with its direct subtasks, notes, and comments. Throws
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
