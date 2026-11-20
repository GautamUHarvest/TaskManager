#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/NotificationRepository.h"

#include <cstdint>
#include <vector>

namespace taskmanager
{

// The caller's own notifications. Blocker alerts are created by
// TaskService::raiseBlocker; comment notifications by CommentService.
class NotificationService
{
  public:
    explicit NotificationService(NotificationRepository &notifications);

    std::vector<NotificationRecord> notifications(const UserRecord &actor);
    // Blocker alerts not yet acknowledged, oldest first, so a client that was
    // offline when one was raised can still show it.
    std::vector<NotificationRecord> pendingBlockers(const UserRecord &actor);
    // Dismisses one of the caller's own alerts so it is not replayed.
    void acknowledge(const UserRecord &actor, std::int64_t notificationId);

  private:
    NotificationRepository &notifications_;
};

}  // namespace taskmanager
