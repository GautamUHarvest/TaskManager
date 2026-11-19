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
    // Applies the engaged fields of `update`, bumps version/updated_at, and
    // records an 'updated' task event. Throws std::invalid_argument when the
    // task does not exist.
    TaskRecord updateTask(const TaskUpdate &update, std::int64_t actorId);
    // Deletes a task and the rows that reference it (notes, events,
    // notifications; assignees and comments cascade). The caller must have
    // already rejected tasks that still have subtasks — see countSubtasks.
    void deleteTask(std::int64_t taskId);
    std::int64_t countSubtasks(std::int64_t parentTaskId);
    std::optional<TaskRecord> findTask(std::int64_t id);
    std::vector<TaskRecord> listSubtasks(std::int64_t parentTaskId);
    std::vector<TaskNoteRecord> listNotes(std::int64_t taskId);

    // --- Notes ---
    std::optional<TaskNoteRecord> findNote(std::int64_t id);
    TaskNoteRecord updateNote(std::int64_t id, const std::string &body);
    void deleteNote(std::int64_t id);
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
    CommentRecord updateComment(std::int64_t id, const std::string &body);
    // Deletes a comment; its replies go with it via the comments
    // parent_comment_id ON DELETE CASCADE (migration 006).
    void deleteComment(std::int64_t id);
    // Number of descendants that would cascade away with this comment, so the
    // UI can warn before deleting a comment that has a thread under it.
    std::int64_t countCommentDescendants(std::int64_t id);

    // --- Notifications ---
    // Returns the stored row so a caller that needs to push it in real time
    // has its id and created_at. Callers that only need the side effect can
    // ignore the result.
    NotificationRecord createNotification(std::int64_t recipientId,
                                          std::int64_t actorId,
                                          std::int64_t taskId,
                                          const std::string &type,
                                          const std::string &message);
    // Unacknowledged blocker alerts for a recipient, oldest first, so the
    // client can replay any it missed while offline.
    std::vector<NotificationRecord> listPendingBlockers(
        std::int64_t recipientId);
    // Stamps read_at on a notification the recipient owns. False when the id
    // does not exist or belongs to someone else; acknowledging one twice is
    // not an error.
    bool acknowledgeNotification(std::int64_t notificationId,
                                 std::int64_t recipientId);

    // --- Blockers ---
    // Flags a task as blocked on `responsibleId` in one transaction: sets the
    // status to 'blocked', bumps the version, records a 'blocked' event, and
    // stores the notification for the responsible member.
    BlockerRaised raiseBlocker(std::int64_t taskId,
                               std::int64_t actorId,
                               std::int64_t responsibleId,
                               const std::string &eventDetail,
                               const std::string &notificationMessage);

    // Returns the user ids assigned to a task.
    std::vector<std::int64_t> listAssigneeIds(std::int64_t taskId);

  private:
    std::string databasePath_;
};

}  // namespace taskmanager
