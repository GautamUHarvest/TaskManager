#include "NotificationRepository.h"

#include "Rows.h"

namespace taskmanager
{

NotificationRepository::NotificationRepository(const db::Database &database)
    : database_(database)
{
}

NotificationRecord NotificationRepository::create(std::int64_t recipientId,
                                                  std::int64_t actorId,
                                                  std::int64_t taskId,
                                                  const std::string &type,
                                                  const std::string &message)
{
    auto connection = database_.connect();
    return rows::insertNotification(
        connection, recipientId, actorId, taskId, type, message);
}

std::vector<NotificationRecord> NotificationRepository::listForRecipient(
    std::int64_t recipientId)
{
    auto connection = database_.connect();
    db::Statement statement(connection,
                            std::string("SELECT ") +
                                rows::kNotificationColumns +
                                " FROM notifications WHERE recipient_id = ?1 "
                                "ORDER BY created_at DESC");
    statement.bindInt64(1, recipientId);
    std::vector<NotificationRecord> notifications;
    while (statement.step())
    {
        notifications.push_back(rows::notification(statement));
    }
    return notifications;
}

std::vector<NotificationRecord> NotificationRepository::listPendingBlockers(
    std::int64_t recipientId)
{
    auto connection = database_.connect();
    db::Statement statement(connection,
                            std::string("SELECT ") +
                                rows::kNotificationColumns +
                                " FROM notifications WHERE recipient_id = ?1 "
                                "AND notification_type = ?2 AND read_at IS "
                                "NULL ORDER BY created_at, id");
    statement.bindInt64(1, recipientId);
    statement.bindText(2, kBlockerNotificationType);
    std::vector<NotificationRecord> pending;
    while (statement.step())
    {
        pending.push_back(rows::notification(statement));
    }
    return pending;
}

bool NotificationRepository::acknowledge(std::int64_t notificationId,
                                         std::int64_t recipientId)
{
    auto connection = database_.connect();
    // Scoped to the recipient so one user cannot dismiss another's alert.
    // Already-acknowledged rows keep their original timestamp and still
    // report success.
    db::Statement update(connection,
                         "UPDATE notifications SET read_at = "
                         "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
                         "WHERE id = ?1 AND recipient_id = ?2 AND read_at IS "
                         "NULL");
    update.bindInt64(1, notificationId);
    update.bindInt64(2, recipientId);
    update.step();

    db::Statement exists(
        connection,
        "SELECT 1 FROM notifications WHERE id = ?1 AND recipient_id = ?2");
    exists.bindInt64(1, notificationId);
    exists.bindInt64(2, recipientId);
    return exists.step();
}

}  // namespace taskmanager
