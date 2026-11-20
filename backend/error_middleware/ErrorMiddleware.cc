#include "ErrorMiddleware.h"

#include "../http/Responses.h"
#include "../security/OriginPolicy.h"

#include <stdexcept>

namespace taskmanager
{
namespace
{
using http::errorResponse;

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
    const auto &origin = request->getHeader("origin");
    if (!security::isAllowedOrigin(origin))
    {
        return;
    }

    response->addHeader("Access-Control-Allow-Origin", origin);
    response->addHeader("Access-Control-Allow-Credentials", "true");
    response->addHeader("Vary", "Origin");
}

// Status for a known error type, or k500InternalServerError.
drogon::HttpStatusCode statusFor(const std::exception &error)
{
    if (dynamic_cast<const UnauthorizedError *>(&error))
    {
        return drogon::k401Unauthorized;
    }
    if (dynamic_cast<const ForbiddenError *>(&error))
    {
        return drogon::k403Forbidden;
    }
    if (dynamic_cast<const DuplicateUserError *>(&error) ||
        dynamic_cast<const UserLimitError *>(&error))
    {
        return drogon::k409Conflict;
    }
    if (dynamic_cast<const TooManyRequestsError *>(&error))
    {
        return drogon::k429TooManyRequests;
    }
    // NotFoundError derives from invalid_argument, so it lands here too.
    if (dynamic_cast<const std::invalid_argument *>(&error))
    {
        return drogon::k400BadRequest;
    }
    return drogon::k500InternalServerError;
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
    const auto status = statusFor(error);
    if (status == drogon::k500InternalServerError)
    {
        LOG_ERROR << "Unhandled request exception: " << error.what();
        callback(errorResponse(status, "Internal server error"));
        return;
    }
    // Registration conflicts use fixed public wording rather than the
    // repository's message.
    if (dynamic_cast<const DuplicateUserError *>(&error))
    {
        callback(errorResponse(status,
                               "Employee ID or email is already registered"));
        return;
    }
    callback(errorResponse(status, error.what()));
}

}  // namespace taskmanager
