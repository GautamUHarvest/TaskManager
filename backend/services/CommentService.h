#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/CommentRepository.h"
#include "../repositories/NotificationRepository.h"
#include "../repositories/TaskRepository.h"

#include <cstdint>
#include <optional>
#include <string>

namespace taskmanager
{

// Threaded task comments. Any member may comment or reply; only the author
// may edit or delete a comment (ForbiddenError otherwise).
class CommentService
{
  public:
    CommentService(CommentRepository &comments,
                   TaskRepository &tasks,
                   NotificationRepository &notifications);

    // Adds a comment, or a reply when parentCommentId is set, and notifies
    // the task's assignees plus (for a reply) the parent comment's author —
    // never the commenter, and nobody twice.
    CommentRecord addComment(const UserRecord &actor,
                             std::int64_t taskId,
                             const std::string &body,
                             const std::optional<std::int64_t> &parentCommentId);
    CommentRecord editComment(const UserRecord &actor,
                              std::int64_t commentId,
                              const std::string &body);
    // Returns how many nested replies were cascade-deleted with it.
    std::int64_t deleteComment(const UserRecord &actor, std::int64_t commentId);

  private:
    CommentRecord requireOwnComment(const UserRecord &actor,
                                    std::int64_t commentId,
                                    const char *forbiddenMessage);

    CommentRepository &comments_;
    TaskRepository &tasks_;
    NotificationRepository &notifications_;
};

}  // namespace taskmanager
