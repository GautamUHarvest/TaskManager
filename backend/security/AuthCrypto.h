#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace taskmanager::security
{

struct AccessClaims
{
    std::int64_t userId;
    std::string sessionId;
    std::int64_t expiresAt;
};

bool validEmail(const std::string &email);
bool validEmployeeId(const std::string &employeeId);
bool validPassword(const std::string &password);
std::string hashPassword(const std::string &password);
bool verifyPassword(const std::string &password, const std::string &encodedHash);

std::string randomToken(std::size_t byteCount);
std::string newSessionId();
std::string sha256Hex(const std::string &value);
std::string issueAccessToken(std::int64_t userId,
                             const std::string &sessionId,
                             const std::string &secret,
                             std::int64_t issuedAt,
                             std::int64_t expiresAt);
std::optional<AccessClaims> verifyAccessToken(const std::string &token,
                                              const std::string &secret,
                                              std::int64_t now);

}  // namespace taskmanager::security
