#include "NotificationController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"

#include <utility>

namespace taskmanager
{
using namespace http;

NotificationController::NotificationController(
    NotificationService &service, const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void NotificationController::notifications(
    const drogon::HttpRequestPtr &request, drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &actor) {
            Json::Value response;
            response["notifications"] =
                toJsonArray(service_.notifications(actor));
            return jsonResponse(drogon::k200OK, response);
        });
}

void NotificationController::pendingBlockers(
    const drogon::HttpRequestPtr &request, drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &actor) {
            Json::Value response;
            response["notifications"] =
                toJsonArray(service_.pendingBlockers(actor));
            return jsonResponse(drogon::k200OK, response);
        });
}

void NotificationController::acknowledge(const drogon::HttpRequestPtr &request,
                                         drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto notificationId =
                requiredInt64(requiredBody(request), "notification_id");
            service_.acknowledge(actor, notificationId);
            Json::Value response;
            response["message"] = "Notification acknowledged";
            response["notification_id"] = Json::Int64(notificationId);
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
