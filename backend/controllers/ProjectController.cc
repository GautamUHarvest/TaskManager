#include "ProjectController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"

#include <utility>

namespace taskmanager
{
using namespace http;

ProjectController::ProjectController(ProjectService &service,
                                     const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void ProjectController::addProject(const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto created =
                service_.addProject(actor,
                                    requiredString(body, "name"),
                                    optionalString(body, "description"));
            Json::Value response;
            response["project"] = toJson(created);
            return jsonResponse(drogon::k201Created, response);
        });
}

void ProjectController::allProjects(const drogon::HttpRequestPtr &request,
                                    drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &) {
            Json::Value response;
            response["projects"] = toJsonArray(service_.allProjects());
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
