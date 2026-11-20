#include "AuthRepository.h"

#include <stdexcept>

namespace taskmanager
{
namespace
{
constexpr const char *kUserColumns =
    "id, employee_id, email, display_name, password_hash, is_active, "
    "email_verified_at IS NOT NULL";

UserRecord userFromStatement(const db::Statement &statement)
{
    return UserRecord{statement.int64Column(0),
                      statement.textColumn(1),
                      statement.textColumn(2),
                      statement.textColumn(3),
                      statement.textColumn(4),
                      statement.int64Column(5) != 0,
                      statement.int64Column(6) != 0};
}

std::optional<UserRecord> verifiedUserForSession(
    const db::Connection &connection,
    const std::string &sessionId,
    const std::string &refreshHash,
    std::int64_t now)
{
    db::Statement statement(
        connection,
        "SELECT u.id, u.employee_id, u.email, u.display_name, u.password_hash, "
        "u.is_active, u.email_verified_at IS NOT NULL "
        "FROM auth_sessions s JOIN users u ON u.id = s.user_id "
        "WHERE s.id = ?1 AND s.refresh_token_hash = ?2 AND s.revoked_at IS "
        "NULL AND s.expires_at > ?3 AND u.is_active = 1 AND "
        "u.email_verified_at IS NOT NULL");
    statement.bindText(1, sessionId);
    statement.bindText(2, refreshHash);
    statement.bindInt64(3, now);
    if (statement.step())
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}
}  // namespace

AuthRepository::AuthRepository(const db::Database &database)
    : database_(database)
{
}

std::int64_t AuthRepository::createUser(const std::string &employeeId,
                                        const std::string &email,
                                        const std::string &displayName,
                                        const std::string &passwordHash)
{
    auto connection = database_.connect();
    try
    {
        db::Transaction transaction(connection);
        db::Statement user(connection,
                           "INSERT INTO users (username, employee_id, email, "
                           "display_name, password_hash, email_verified_at) "
                           "SELECT ?1, ?1, ?2, ?3, ?4, "
                           "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE "
                           "(SELECT count(*) FROM users WHERE "
                           "is_active = 1) < 25");
        user.bindText(1, employeeId);
        user.bindText(2, email);
        user.bindText(3, displayName);
        user.bindText(4, passwordHash);
        user.step();
        if (connection.changes() != 1)
        {
            throw UserLimitError("The maximum of 25 active users is reached");
        }
        const std::int64_t userId = connection.lastInsertRowId();
        transaction.commit();
        return userId;
    }
    catch (const db::SqliteError &error)
    {
        if (error.isConstraint())
        {
            throw DuplicateUserError("Employee ID or email already exists");
        }
        throw;
    }
}

std::optional<UserRecord> AuthRepository::findUserByLogin(
    const std::string &login)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        std::string("SELECT ") + kUserColumns +
            " FROM users WHERE employee_id = ?1 COLLATE NOCASE OR email = ?1 "
            "COLLATE NOCASE LIMIT 1");
    statement.bindText(1, login);
    if (statement.step())
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}

std::optional<UserRecord> AuthRepository::findVerifiedUserById(
    std::int64_t userId)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        std::string("SELECT ") + kUserColumns +
            " FROM users WHERE id = ?1 AND is_active = 1 AND "
            "email_verified_at IS NOT NULL");
    statement.bindInt64(1, userId);
    if (statement.step())
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}

void AuthRepository::createSession(std::int64_t userId,
                                   const std::string &sessionId,
                                   const std::string &refreshHash,
                                   std::int64_t expiresAt)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        "INSERT INTO auth_sessions(id, user_id, refresh_token_hash, expires_at) "
        "SELECT ?1, id, ?3, ?4 FROM users WHERE id = ?2 AND is_active = 1 "
        "AND email_verified_at IS NOT NULL");
    statement.bindText(1, sessionId);
    statement.bindInt64(2, userId);
    statement.bindText(3, refreshHash);
    statement.bindInt64(4, expiresAt);
    statement.step();
    if (connection.changes() != 1)
    {
        throw std::runtime_error("Unable to create authentication session");
    }
}

std::optional<UserRecord> AuthRepository::rotateSession(
    const std::string &sessionId,
    const std::string &oldRefreshHash,
    const std::string &newRefreshHash,
    std::int64_t now,
    std::int64_t newExpiresAt)
{
    auto connection = database_.connect();
    db::Transaction transaction(connection);
    auto user =
        verifiedUserForSession(connection, sessionId, oldRefreshHash, now);
    if (!user)
    {
        return std::nullopt;  // Transaction rolls back on scope exit.
    }
    db::Statement update(
        connection,
        "UPDATE auth_sessions SET refresh_token_hash = ?1, expires_at = "
        "?2 WHERE id = ?3 AND refresh_token_hash = ?4 AND revoked_at IS "
        "NULL AND expires_at > ?5");
    update.bindText(1, newRefreshHash);
    update.bindInt64(2, newExpiresAt);
    update.bindText(3, sessionId);
    update.bindText(4, oldRefreshHash);
    update.bindInt64(5, now);
    update.step();
    if (connection.changes() != 1)
    {
        return std::nullopt;
    }
    transaction.commit();
    return user;
}

bool AuthRepository::revokeSession(const std::string &sessionId,
                                   std::int64_t userId)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        "UPDATE auth_sessions SET revoked_at = unixepoch() WHERE id = ?1 AND "
        "user_id = ?2 AND revoked_at IS NULL");
    statement.bindText(1, sessionId);
    statement.bindInt64(2, userId);
    statement.step();
    return connection.changes() == 1;
}

}  // namespace taskmanager
