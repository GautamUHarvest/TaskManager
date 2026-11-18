#pragma once

#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>

namespace taskmanager
{

class DuplicateUserError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

class UserLimitError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

class AuthRepository
{
  public:
    AuthRepository(std::string databasePath, std::string migrationsPath);

    void initialize();
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
    std::string databasePath_;
    std::string migrationsPath_;
};

}  // namespace taskmanager
