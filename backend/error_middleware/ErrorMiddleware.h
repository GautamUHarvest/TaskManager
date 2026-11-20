#pragma once

#include "../common/Errors.h"

#include <drogon/HttpMiddleware.h>

#include <exception>

namespace taskmanager
{

// Normalizes every API error to {"error": "..."} with no-store caching, and
// adds CORS headers for allowed origins. The exception -> status mapping is
// documented in common/Errors.h.
//
// Two entry points must stay consistent: invoke() for responses produced by
// matched routes, and handleException()/notFoundResponse(), which main.cc
// also installs as Drogon's exception and default (404) handlers.
class ErrorMiddleware
    : public drogon::HttpMiddleware<ErrorMiddleware, false>
{
  public:
    void invoke(const drogon::HttpRequestPtr &request,
                drogon::MiddlewareNextCallback &&next,
                drogon::MiddlewareCallback &&callback) override;

    static void handleException(
        const std::exception &error,
        const drogon::HttpRequestPtr &request,
        drogon::AdviceCallback &&callback);
    static drogon::HttpResponsePtr notFoundResponse();
};

}  // namespace taskmanager
