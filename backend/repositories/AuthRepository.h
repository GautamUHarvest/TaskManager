#pragma once

#include "../common/Errors.h"
#include "../db/Sqlite.h"
#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <string>

namespace taskmanager
{

// Accounts and refresh-token sessions. Schema setup is not done here — see
// db::initializeDatabase, which must run first.
class AuthRepository
{
  public:
    explicit AuthRepository(const db::Database &database);

    // Throws DuplicateUserError when the employee ID or email is taken (or
    // the email fails the domain trigger), UserLimitError at 25 active users.
    std::int64_t createUser(const std::string &employeeId,
                            const std::string &email,
                            const std::string &displayName,
                            const std::string &passwordHash);
    std::optional<UserRecord> findUserByLogin(const std::string &login);
    std::optional<UserRecord> findVerifiedUserById(std::int64_t userId);
    void createSession(std::int64_t userId,
                       const std::string &sessionId,
                       const std::string &refreshHash,
                       std::int64_t expiresAt);
    std::optional<UserRecord> rotateSession(
        const std::string &sessionId,
        const std::string &oldRefreshHash,
        const std::string &newRefreshHash,
        std::int64_t now,
        std::int64_t newExpiresAt);
    bool revokeSession(const std::string &sessionId, std::int64_t userId);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
