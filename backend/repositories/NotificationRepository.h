#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"

#include <cstdint>
#include <string>
#include <vector>

namespace taskmanager
{

class NotificationRepository
{
  public:
    explicit NotificationRepository(const db::Database &database);

    // Returns the stored row (id, created_at) so it can be pushed live.
    NotificationRecord create(std::int64_t recipientId,
                              std::int64_t actorId,
                              std::int64_t taskId,
                              const std::string &type,
                              const std::string &message);
    // Newest first.
    std::vector<NotificationRecord> listForRecipient(std::int64_t recipientId);
    // Unacknowledged blocker alerts for a recipient, oldest first, so the
    // client can replay any it missed while offline.
    std::vector<NotificationRecord> listPendingBlockers(
        std::int64_t recipientId);
    // Stamps read_at on a notification the recipient owns. False when the id
    // does not exist or belongs to someone else; acknowledging one twice is
    // not an error.
    bool acknowledge(std::int64_t notificationId, std::int64_t recipientId);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
