#include "AuthService.h"

#include "../common/Text.h"

#include <algorithm>
#include <cctype>
#include <ctime>
#include <stdexcept>
#include <utility>

namespace taskmanager
{
using text::lowercase;
using text::trim;

namespace
{
constexpr std::int64_t kRefreshLifetimeSeconds = 30 * 24 * 60 * 60;
constexpr std::int64_t kAccessLifetimeSeconds = 10 * 60;

std::int64_t nowSeconds()
{
    return static_cast<std::int64_t>(std::time(nullptr));
}

struct ParsedRefreshToken
{
    std::string sessionId;
    std::string token;
};

std::optional<ParsedRefreshToken> parseRefreshToken(const std::string &token)
{
    const auto separator = token.find('.');
    if (separator != 32 || token.size() < 64 ||
        token.find('.', separator + 1) != std::string::npos)
    {
        return std::nullopt;
    }
    const std::string sessionId = token.substr(0, separator);
    if (!std::all_of(sessionId.begin(), sessionId.end(), [](unsigned char c) {
            return std::isxdigit(c) != 0;
        }))
    {
        return std::nullopt;
    }
    return ParsedRefreshToken{sessionId, token};
}
}  // namespace

AuthService::AuthService(AuthRepository &repository, std::string jwtSecret)
    : repository_(repository), jwtSecret_(std::move(jwtSecret))
{
    if (jwtSecret_.size() < 32)
    {
        throw std::invalid_argument(
            "TASK_MANAGER_JWT_SECRET must contain at least 32 bytes");
    }
}

std::int64_t AuthService::registerUser(const std::string &employeeId,
                                      const std::string &email,
                                      const std::string &displayName,
                                      const std::string &password)
{
    const std::string normalizedEmployeeId = trim(employeeId);
    const std::string normalizedEmail = lowercase(trim(email));
    const std::string normalizedDisplayName = trim(displayName);
    if (!security::validEmployeeId(normalizedEmployeeId))
    {
        throw std::invalid_argument("Invalid employee ID");
    }
    if (!security::validEmail(normalizedEmail))
    {
        throw std::invalid_argument("Email must be a valid @uharvest.in address");
    }
    if (normalizedDisplayName.empty() || normalizedDisplayName.size() > 100)
    {
        throw std::invalid_argument("Display name must be 1 to 100 characters");
    }
    if (!security::validPassword(password))
    {
        throw std::invalid_argument(
            "Password must be at least 6 characters and include an uppercase "
            "letter, a number, and a special character");
    }

    return repository_.createUser(
        normalizedEmployeeId,
        normalizedEmail,
        normalizedDisplayName,
        security::hashPassword(password));
}

AuthTokens AuthService::login(const std::string &login,
                              const std::string &password)
{
    const std::string normalizedLogin = trim(login);
    if (normalizedLogin.empty() || normalizedLogin.size() > 254 ||
        password.size() > 1024)
    {
        throw std::invalid_argument("Invalid credentials");
    }
    auto user = repository_.findUserByLogin(
        normalizedLogin.find('@') == std::string::npos
            ? normalizedLogin
            : lowercase(normalizedLogin));
    static const std::string dummyHash =
        security::hashPassword("DummY-Passw0rd!");
    const std::string &hash = user ? user->passwordHash : dummyHash;
    const bool passwordMatches = security::verifyPassword(password, hash);
    if (!user || !passwordMatches || !user->active || !user->emailVerified)
    {
        throw UnauthorizedError("Invalid employee ID/email or password");
    }
    return issueTokens(*user);
}

AuthTokens AuthService::refresh(const std::string &refreshToken)
{
    const auto parsed = parseRefreshToken(refreshToken);
    if (!parsed)
    {
        throw UnauthorizedError("Invalid refresh token");
    }
    const auto now = nowSeconds();
    const std::string newRefreshToken =
        parsed->sessionId + "." + security::randomToken(32);
    auto user = repository_.rotateSession(parsed->sessionId,
                                          security::sha256Hex(parsed->token),
                                          security::sha256Hex(newRefreshToken),
                                          now,
                                          now + kRefreshLifetimeSeconds);
    if (!user)
    {
        throw UnauthorizedError("Invalid or expired refresh token");
    }
    const auto accessExpires = now + kAccessLifetimeSeconds;
    return AuthTokens{*user,
                      security::issueAccessToken(user->id,
                                                 parsed->sessionId,
                                                 jwtSecret_,
                                                 now,
                                                 accessExpires),
                      newRefreshToken,
                      kAccessLifetimeSeconds};
}

bool AuthService::logout(const std::string &accessToken)
{
    const auto claims =
        security::verifyAccessToken(accessToken, jwtSecret_, nowSeconds());
    if (!claims)
    {
        throw UnauthorizedError("Invalid or expired access token");
    }
    return repository_.revokeSession(claims->sessionId, claims->userId);
}

UserRecord AuthService::profile(const std::string &accessToken)
{
    const auto claims =
        security::verifyAccessToken(accessToken, jwtSecret_, nowSeconds());
    if (!claims)
    {
        throw UnauthorizedError("Invalid or expired access token");
    }
    auto user = repository_.findVerifiedUserById(claims->userId);
    if (!user)
    {
        throw UnauthorizedError("Invalid or expired access token");
    }
    return *user;
}

AuthTokens AuthService::issueTokens(const UserRecord &user)
{
    const auto now = nowSeconds();
    const std::string sessionId = security::newSessionId();
    const std::string refreshToken =
        sessionId + "." + security::randomToken(32);
    repository_.createSession(user.id,
                              sessionId,
                              security::sha256Hex(refreshToken),
                              now + kRefreshLifetimeSeconds);
    return AuthTokens{user,
                      security::issueAccessToken(user.id,
                                                 sessionId,
                                                 jwtSecret_,
                                                 now,
                                                 now + kAccessLifetimeSeconds),
                      refreshToken,
                      kAccessLifetimeSeconds};
}

}  // namespace taskmanager
