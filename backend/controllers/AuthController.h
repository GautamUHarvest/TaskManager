#pragma once

#include <drogon/HttpAppFramework.h>
#include <trantor/utils/TaskQueue.h>

#include "../services/AuthService.h"

namespace taskmanager
{

class AuthController
{
  public:
    AuthController(AuthService &service, trantor::TaskQueue &workers);

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
    template <typename Work>
    void run(const drogon::HttpRequestPtr &request,
             drogon::AdviceCallback &&callback,
             Work work);

    AuthService &service_;
    trantor::TaskQueue &workers_;
};

}  // namespace taskmanager
