#pragma once

#include <drogon/HttpMiddleware.h>

#include <exception>
#include <stdexcept>

namespace taskmanager
{

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

class TooManyRequestsError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

}  // namespace taskmanager
