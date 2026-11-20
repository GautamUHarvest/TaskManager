#pragma once

#include "../http/Dispatcher.h"
#include "../services/UserService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/user/all.
class UserController
{
  public:
    UserController(UserService &service, const http::Dispatcher &dispatcher);

    void allUsers(const drogon::HttpRequestPtr &request,
                  drogon::AdviceCallback &&callback);

  private:
    UserService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
