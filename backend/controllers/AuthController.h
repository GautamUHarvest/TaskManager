#pragma once

#include "../http/Dispatcher.h"
#include "../security/RateLimiter.h"
#include "../services/AuthService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/auth/*: register, login, refresh, logout, me.
class AuthController
{
  public:
    AuthController(AuthService &service, const http::Dispatcher &dispatcher);

    void registerUser(const drogon::HttpRequestPtr &request,
                      drogon::AdviceCallback &&callback);
    void login(const drogon::HttpRequestPtr &request,
               drogon::AdviceCallback &&callback);
    void refresh(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void logout(const drogon::HttpRequestPtr &request,
                drogon::AdviceCallback &&callback);
    void profile(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);

  private:
    AuthService &service_;
    const http::Dispatcher &dispatcher_;
    // Per client IP.
    security::RateLimiter registerLimiter_;
    security::RateLimiter loginLimiter_;
};

}  // namespace taskmanager
