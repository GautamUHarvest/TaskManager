#pragma once

#include "../repositories/AuthRepository.h"
#include "../security/AuthCrypto.h"

#include <cstdint>
#include <stdexcept>
#include <string>

namespace taskmanager
{

class VerificationMailer
{
  public:
    virtual ~VerificationMailer() = default;
    virtual void sendVerificationCode(const std::string &email,
                                      const std::string &token) = 0;
};

class UnauthorizedError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

struct AuthTokens
{
    UserRecord user;
    std::string accessToken;
    std::string refreshToken;
    std::int64_t accessExpiresIn;
};

class AuthService
{
  public:
    AuthService(AuthRepository &repository, std::string jwtSecret);

    std::int64_t registerUser(const std::string &employeeId,
                              const std::string &email,
                              const std::string &displayName,
                              const std::string &password);
    AuthTokens login(const std::string &login, const std::string &password);
    AuthTokens refresh(const std::string &refreshToken);
    bool logout(const std::string &accessToken);
    UserRecord profile(const std::string &accessToken);

  private:
    AuthTokens issueTokens(const UserRecord &user);
    AuthRepository &repository_;
    std::string jwtSecret_;
};

}  // namespace taskmanager
