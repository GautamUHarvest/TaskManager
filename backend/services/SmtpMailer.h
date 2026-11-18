#pragma once

#include "AuthService.h"

#include <cstdint>
#include <string>

namespace taskmanager
{

class SmtpMailer final : public VerificationMailer
{
  public:
    SmtpMailer(std::string host,
               std::uint16_t port,
               std::string username,
               std::string password,
               std::string fromAddress);

    static SmtpMailer fromEnvironment();
    void sendVerificationCode(const std::string &email,
                              const std::string &token) override;

  private:
    std::string host_;
    std::uint16_t port_;
    std::string username_;
    std::string password_;
    std::string fromAddress_;
};

}  // namespace taskmanager
