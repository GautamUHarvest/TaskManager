#include "AuthRoutes.h"

#include "../controllers/AuthController.h"
#include "../security/OriginPolicy.h"

#include <drogon/HttpAppFramework.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>

namespace taskmanager
{
namespace
{
bool isAuthRoute(const std::string &path)
{
    constexpr std::array<std::string_view, 5> paths = {
        "/api/auth/register",
        "/api/auth/login",
        "/api/auth/refresh",
        "/api/auth/logout",
        "/api/auth/me"};

    return std::find(paths.begin(), paths.end(), path) != paths.end();
}

std::string expectedMethod(const std::string &path)
{
    return path == "/api/auth/me" ? "GET" : "POST";
}

bool hasOnlyAllowedHeaders(const std::string &headers)
{
    std::istringstream stream(headers);
    std::string header;
    while (std::getline(stream, header, ','))
    {
        const auto first = header.find_first_not_of(" \t");
        const auto last = header.find_last_not_of(" \t");
        if (first == std::string::npos)
        {
            continue;
        }
        header = header.substr(first, last - first + 1);
        std::transform(header.begin(),
                       header.end(),
                       header.begin(),
                       [](unsigned char character) {
                           return static_cast<char>(std::tolower(character));
                       });
        if (header != "authorization" && header != "content-type")
        {
            return false;
        }
    }
    return true;
}

drogon::HttpResponsePtr corsPreflightResponse(
    const drogon::HttpRequestPtr &request)
{
    auto response = drogon::HttpResponse::newHttpResponse();
    response->addHeader("Vary", "Origin");

    const auto &origin = request->getHeader("origin");
    if (!security::isAllowedOrigin(origin))
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    const auto &requestedMethod =
        request->getHeader("access-control-request-method");
    if (requestedMethod != expectedMethod(request->path()))
    {
        response->setStatusCode(drogon::k405MethodNotAllowed);
        return response;
    }
    if (!hasOnlyAllowedHeaders(
            request->getHeader("access-control-request-headers")))
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    response->setStatusCode(drogon::k204NoContent);
    response->addHeader("Access-Control-Allow-Origin", origin);
    response->addHeader("Access-Control-Allow-Credentials", "true");
    response->addHeader("Access-Control-Allow-Methods", requestedMethod);
    response->addHeader("Access-Control-Allow-Headers",
                        "Authorization, Content-Type");
    response->addHeader("Access-Control-Max-Age", "600");
    return response;
}
}  // namespace

void registerAuthRoutes(const std::shared_ptr<AuthController> &controller)
{
    auto &app = drogon::app();
    app.registerSyncAdvice([](const drogon::HttpRequestPtr &request) {
        if (request->method() != drogon::Options)
        {
            return drogon::HttpResponsePtr{};
        }
        if (!isAuthRoute(request->path()))
        {
            // Not an auth route: pass through so other route groups' preflight
            // advice (e.g. TaskRoutes) can handle their own OPTIONS. Truly
            // unknown OPTIONS paths fall through to the default 404 handler.
            return drogon::HttpResponsePtr{};
        }
        return corsPreflightResponse(request);
    });

    app.registerHandler(
        "/api/auth/register",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->registerUser(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/auth/login",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->login(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/auth/refresh",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->refresh(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/auth/logout",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->logout(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/auth/me",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->profile(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});
}

}  // namespace taskmanager
