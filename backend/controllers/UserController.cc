#include "UserController.h"

#include "../http/JsonMappers.h"
#include "../http/Responses.h"

#include <utility>

namespace taskmanager
{

UserController::UserController(UserService &service,
                               const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void UserController::allUsers(const drogon::HttpRequestPtr &request,
                              drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &) {
            Json::Value response;
            response["users"] = http::toJsonArray(service_.allUsers());
            return http::jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
