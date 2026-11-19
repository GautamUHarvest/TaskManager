#include "ErrorMiddleware.h"

#include "../repositories/AuthRepository.h"
#include "../services/AuthService.h"

#include <json/json.h>

#include <cstdlib>

namespace taskmanager
{
namespace
{
drogon::HttpResponsePtr errorResponse(drogon::HttpStatusCode status,
                                      const std::string &message)
{
    Json::Value body;
    body["error"] = message;
    auto response = drogon::HttpResponse::newHttpJsonResponse(body);
    response->setStatusCode(status);
    response->addHeader("Cache-Control", "no-store");
    response->addHeader("Pragma", "no-cache");
    return response;
}

drogon::HttpResponsePtr normalizeErrorResponse(
    const drogon::HttpResponsePtr &response)
{
    if (!response)
    {
        return errorResponse(drogon::k500InternalServerError,
                             "Internal server error");
    }

    if (response->statusCode() < drogon::k400BadRequest)
    {
        return response;
    }

    response->addHeader("Cache-Control", "no-store");
    response->addHeader("Pragma", "no-cache");
    if (response->body().empty())
    {
        return errorResponse(response->statusCode(), "Request failed");
    }
    return response;
}

void addCorsHeaders(const drogon::HttpRequestPtr &request,
                    const drogon::HttpResponsePtr &response)
{
    const auto *allowedOrigin = std::getenv("TASK_MANAGER_CORS_ORIGIN");
    const auto &origin = request->getHeader("origin");
    if (!allowedOrigin || allowedOrigin[0] == '\0' ||
        origin != allowedOrigin)
    {
        return;
    }

    response->addHeader("Access-Control-Allow-Origin", origin);
    response->addHeader("Access-Control-Allow-Credentials", "true");
    response->addHeader("Vary", "Origin");
}
}  // namespace

void ErrorMiddleware::invoke(
    const drogon::HttpRequestPtr &request,
    drogon::MiddlewareNextCallback &&next,
    drogon::MiddlewareCallback &&callback)
{
    next([request, callback = std::move(callback)](
             const drogon::HttpResponsePtr &response) {
        auto normalized = normalizeErrorResponse(response);
        addCorsHeaders(request, normalized);
        callback(normalized);
    });
}

drogon::HttpResponsePtr ErrorMiddleware::notFoundResponse()
{
    return errorResponse(drogon::k404NotFound, "Route not found");
}

void ErrorMiddleware::handleException(
    const std::exception &error,
    const drogon::HttpRequestPtr &,
    drogon::AdviceCallback &&callback)
{
    if (dynamic_cast<const DuplicateUserError *>(&error))
    {
        callback(errorResponse(drogon::k409Conflict,
                               "Employee ID or email is already registered"));
        return;
    }
    if (const auto *limit = dynamic_cast<const UserLimitError *>(&error))
    {
        callback(errorResponse(drogon::k409Conflict, limit->what()));
        return;
    }
    if (const auto *unauthorized = dynamic_cast<const UnauthorizedError *>(&error))
    {
        callback(errorResponse(drogon::k401Unauthorized, unauthorized->what()));
        return;
    }
    if (const auto *forbidden = dynamic_cast<const ForbiddenError *>(&error))
    {
        callback(errorResponse(drogon::k403Forbidden, forbidden->what()));
        return;
    }
    if (const auto *rateLimit =
            dynamic_cast<const TooManyRequestsError *>(&error))
    {
        callback(errorResponse(drogon::k429TooManyRequests, rateLimit->what()));
        return;
    }
    if (const auto *invalid = dynamic_cast<const std::invalid_argument *>(&error))
    {
        callback(errorResponse(drogon::k400BadRequest, invalid->what()));
        return;
    }

    LOG_ERROR << "Unhandled request exception: " << error.what();
    callback(errorResponse(drogon::k500InternalServerError,
                           "Internal server error"));
}

}  // namespace taskmanager
