#include "NotificationService.h"

#include "../common/Errors.h"
#include "TaskRules.h"

namespace taskmanager
{

NotificationService::NotificationService(NotificationRepository &notifications)
    : notifications_(notifications)
{
}

std::vector<NotificationRecord> NotificationService::notifications(
    const UserRecord &actor)
{
    return notifications_.listForRecipient(actor.id);
}

std::vector<NotificationRecord> NotificationService::pendingBlockers(
    const UserRecord &actor)
{
    return notifications_.listPendingBlockers(actor.id);
}

void NotificationService::acknowledge(const UserRecord &actor,
                                      std::int64_t notificationId)
{
    rules::requirePositiveId(notificationId, "notification_id");
    if (!notifications_.acknowledge(notificationId, actor.id))
    {
        // Covers both "no such row" and "belongs to someone else" — not
        // distinguished, so one user cannot probe for another's ids.
        throw NotFoundError("Notification not found");
    }
}

}  // namespace taskmanager
