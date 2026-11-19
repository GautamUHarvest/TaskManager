#include "AuthController.h"

#include "../error_middleware/ErrorMiddleware.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>

namespace taskmanager
{
namespace
{
Json::Value requiredBody(const drogon::HttpRequestPtr &request)
{
    const auto &body = request->getJsonObject();
    if (!body || !body->isObject())
    {
        throw std::invalid_argument("A JSON request body is required");
    }
    return *body;
}

std::string requiredString(const Json::Value &body, const char *field)
{
    if (!body.isMember(field) || !body[field].isString() ||
        body[field].asString().empty())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' is required");
    }
    return body[field].asString();
}

std::string bearerToken(const drogon::HttpRequestPtr &request)
{
    const auto &authorization = request->getHeader("authorization");
    if (authorization.size() <= 7)
    {
        throw UnauthorizedError("A bearer access token is required");
    }

    std::string scheme = authorization.substr(0, 7);
    std::transform(scheme.begin(),
                   scheme.end(),
                   scheme.begin(),
                   [](unsigned char character) {
                       return static_cast<char>(std::tolower(character));
                   });
    if (scheme != "bearer ")
    {
        throw UnauthorizedError("A bearer access token is required");
    }
    return authorization.substr(7);
}

drogon::HttpResponsePtr jsonResponse(drogon::HttpStatusCode status,
                                     const Json::Value &body)
{
    auto response = drogon::HttpResponse::newHttpJsonResponse(body);
    response->setStatusCode(status);
    response->addHeader("Cache-Control", "no-store");
    response->addHeader("Pragma", "no-cache");
    return response;
}

Json::Value userJson(const UserRecord &user)
{
    Json::Value body;
    body["id"] = Json::Int64(user.id);
    body["employee_id"] = user.employeeId;
    body["email"] = user.email;
    body["display_name"] = user.displayName;
    return body;
}

// Response body for login/refresh. The refresh token is NOT in the body;
// it is delivered to the browser in an HttpOnly, Secure, SameSite=Strict
// cookie scoped to /api/auth, so JavaScript cannot read it and it is only
// ever sent back on auth endpoints.
Json::Value tokensJson(const AuthTokens &tokens)
{
    Json::Value body;
    body["access_token"] = tokens.accessToken;
    body["token_type"] = "Bearer";
    body["expires_in"] = Json::Int64(tokens.accessExpiresIn);
    body["user"] = userJson(tokens.user);
    return body;
}

constexpr const char *kRefreshCookieName = "refresh_token";
constexpr const char *kRefreshCookiePath = "/api/auth";
constexpr int kRefreshCookieMaxAgeSeconds = 30 * 24 * 60 * 60;

// SameSite for the refresh cookie. Default "Strict" is right for production
// (frontend and backend served from one origin behind nginx). The dev setup
// serves Flutter over http://localhost:5000 and the backend over
// https://localhost:5555 — Chrome's schemeful same-site treats those as
// cross-site, which makes Strict/Lax drop the cookie silently. Set
// TASK_MANAGER_REFRESH_COOKIE_SAMESITE=None for that case (we already set
// Secure, which None requires).
std::string refreshCookieSameSite()
{
    const char *value = std::getenv("TASK_MANAGER_REFRESH_COOKIE_SAMESITE");
    if (!value || value[0] == '\0')
    {
        return "Strict";
    }
    const std::string text(value);
    if (text == "Strict" || text == "Lax" || text == "None")
    {
        return text;
    }
    return "Strict";
}

drogon::Cookie makeRefreshCookie(const std::string &value, int maxAge)
{
    drogon::Cookie cookie(kRefreshCookieName, value);
    cookie.setHttpOnly(true);
    cookie.setSecure(true);
    cookie.setPath(kRefreshCookiePath);
    cookie.setMaxAge(maxAge);
    cookie.setSameSite(refreshCookieSameSite());
    return cookie;
}

void setRefreshCookie(const drogon::HttpResponsePtr &response,
                      const std::string &value)
{
    response->addCookie(makeRefreshCookie(value, kRefreshCookieMaxAgeSeconds));
}

void clearRefreshCookie(const drogon::HttpResponsePtr &response)
{
    // Overwrite with an empty, immediately expired cookie at the same path.
    response->addCookie(makeRefreshCookie(std::string(), 0));
}

std::string requiredRefreshCookie(const drogon::HttpRequestPtr &request)
{
    const auto &value = request->getCookie(kRefreshCookieName);
    if (value.empty())
    {
        throw UnauthorizedError("Missing refresh token");
    }
    return value;
}

void requireRateLimit(const drogon::HttpRequestPtr &request,
                      const std::string &key,
                      std::size_t count,
                      std::chrono::seconds period)
{
    struct Window
    {
        std::chrono::steady_clock::time_point start;
        std::size_t count{0};
    };
    static std::mutex mutex;
    static std::unordered_map<std::string, Window> windows;
    const auto now = std::chrono::steady_clock::now();
    const auto limiterKey = key + ':' + request->getPeerAddr().toIp();
    std::lock_guard<std::mutex> lock(mutex);
    auto &window = windows[limiterKey];
    if (window.start.time_since_epoch().count() == 0 ||
        now - window.start >= period)
    {
        window = Window{now, 0};
    }
    if (window.count >= count)
    {
        throw TooManyRequestsError("Too many requests");
    }
    ++window.count;
    if (windows.size() > 4096)
    {
        for (auto item = windows.begin(); item != windows.end();)
        {
            if (now - item->second.start >= period)
            {
                item = windows.erase(item);
            }
            else
            {
                ++item;
            }
        }
    }
}
}  // namespace

AuthController::AuthController(AuthService &service,
                               trantor::TaskQueue &workers)
    : service_(service), workers_(workers)
{
}

template <typename Work>
void AuthController::run(const drogon::HttpRequestPtr &request,
                         drogon::AdviceCallback &&callback,
                         Work work)
{
    workers_.runTaskInQueue(
            [request,
             work = std::move(work),
             callback = std::move(callback)]() mutable {
                try
                {
                    callback(work());
                }
                catch (const std::exception &error)
                {
                    ErrorMiddleware::handleException(
                        error, request, std::move(callback));
                }
            });
}

void AuthController::registerUser(const drogon::HttpRequestPtr &request,
                                  drogon::AdviceCallback &&callback)
{
    const auto body = requiredBody(request);
    requireRateLimit(request, "register", 20, std::chrono::hours(1));
    run(request,
        std::move(callback),
        [this, body]() {
            const auto userId = service_.
            registerUser(
                requiredString(body, "employee_id"),
                requiredString(body, "email"),
                requiredString(body, "display_name"),
                requiredString(body, "password"));
            Json::Value response;
            response["message"] = "Account created. You can now sign in";
            response["user_id"] = Json::Int64(userId);
            return jsonResponse(drogon::k201Created, response);
        });
}

void AuthController::login(const drogon::HttpRequestPtr &request,
                           drogon::AdviceCallback &&callback)
{
    const auto body = requiredBody(request);
    requireRateLimit(request, "login", 60, std::chrono::minutes(1));
    run(request,
        std::move(callback),
        [this, body]() {
            const auto tokens =
                service_.login(requiredString(body, "login"),
                               requiredString(body, "password"));
            auto response = jsonResponse(drogon::k200OK, tokensJson(tokens));
            setRefreshCookie(response, tokens.refreshToken);
            return response;
        });
}

void AuthController::refresh(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    // The refresh token is the HttpOnly cookie set on login; no request body.
    // AuthService::refresh rotates the token on every call, and we overwrite
    // the cookie with the new one so each refresh issues a fresh credential.
    const auto cookieToken = requiredRefreshCookie(request);
    run(request,
        std::move(callback),
        [this, cookieToken]() {
            const auto tokens = service_.refresh(cookieToken);
            auto response = jsonResponse(drogon::k200OK, tokensJson(tokens));
            setRefreshCookie(response, tokens.refreshToken);
            return response;
        });
}

void AuthController::logout(const drogon::HttpRequestPtr &request,
                            drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request,
        std::move(callback),
        [this, token]() {
            service_.logout(token);
            auto response = drogon::HttpResponse::newHttpResponse();
            response->setStatusCode(drogon::k204NoContent);
            response->addHeader("Cache-Control", "no-store");
            clearRefreshCookie(response);
            return response;
        });
}

void AuthController::profile(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request,
        std::move(callback),
        [this, token]() {
            Json::Value response;
            response["user"] = userJson(service_.profile(token));
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
