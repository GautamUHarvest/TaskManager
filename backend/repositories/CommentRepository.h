#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

// Threaded task comments. Replies reference their parent via
// parent_comment_id, which is ON DELETE CASCADE (migration 006).
class CommentRepository
{
  public:
    explicit CommentRepository(const db::Database &database);

    // Throws std::invalid_argument when the task or parent comment is missing.
    CommentRecord add(const NewComment &comment);
    // Oldest first; the client rebuilds the thread from parent ids.
    std::vector<CommentRecord> listForTask(std::int64_t taskId);
    std::optional<CommentRecord> find(std::int64_t id);
    // Throws NotFoundError when the comment does not exist.
    CommentRecord update(std::int64_t id, const std::string &body);
    // Deletes the comment; its replies go with it by cascade.
    void remove(std::int64_t id);
    // How many replies (at any depth) would cascade away with this comment.
    std::int64_t countDescendants(std::int64_t id);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
