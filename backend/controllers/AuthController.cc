#include "AuthController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"

#include <chrono>
#include <utility>

namespace taskmanager
{
namespace
{
using http::jsonResponse;
using http::requiredBody;
using http::requiredString;

// Response body for login/refresh. The refresh token is returned in the JSON
// body: the client stores it (localStorage) and sends it back in the
// /auth/refresh request body. SECURITY NOTE: this is the localStorage token
// model — the refresh token is readable by JavaScript and therefore exposed to
// XSS. It was chosen deliberately so the app works over plain HTTP on a
// LAN/demo box (no Secure-cookie / HTTPS requirement). For production, prefer
// the HttpOnly-cookie model over HTTPS. See apirequirement.md.
Json::Value tokensJson(const AuthTokens &tokens)
{
    Json::Value body;
    body["access_token"] = tokens.accessToken;
    body["refresh_token"] = tokens.refreshToken;
    body["token_type"] = "Bearer";
    body["expires_in"] = Json::Int64(tokens.accessExpiresIn);
    body["user"] = http::toJson(tokens.user);
    return body;
}

std::string clientKey(const char *action, const drogon::HttpRequestPtr &request)
{
    return std::string(action) + ':' + request->getPeerAddr().toIp();
}
}  // namespace

AuthController::AuthController(AuthService &service,
                               const http::Dispatcher &dispatcher)
    : service_(service),
      dispatcher_(dispatcher),
      registerLimiter_(20, std::chrono::hours(1)),
      loginLimiter_(60, std::chrono::minutes(1))
{
}

void AuthController::registerUser(const drogon::HttpRequestPtr &request,
                                  drogon::AdviceCallback &&callback)
{
    const auto body = requiredBody(request);
    registerLimiter_.acquire(clientKey("register", request));
    dispatcher_.run(request, std::move(callback), [this, body]() {
        const auto userId =
            service_.registerUser(requiredString(body, "employee_id"),
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
    loginLimiter_.acquire(clientKey("login", request));
    dispatcher_.run(request, std::move(callback), [this, body]() {
        const auto tokens = service_.login(requiredString(body, "login"),
                                           requiredString(body, "password"));
        return jsonResponse(drogon::k200OK, tokensJson(tokens));
    });
}

void AuthController::refresh(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    // The client sends its stored refresh token in the body. It is rotated on
    // every call, so the response carries a new one to persist in its place.
    const auto body = requiredBody(request);
    dispatcher_.run(request, std::move(callback), [this, body]() {
        const auto tokens =
            service_.refresh(requiredString(body, "refresh_token"));
        return jsonResponse(drogon::k200OK, tokensJson(tokens));
    });
}

void AuthController::logout(const drogon::HttpRequestPtr &request,
                            drogon::AdviceCallback &&callback)
{
    // Needs the raw token (it names the session to revoke), so this uses
    // run() rather than authenticated().
    const auto token = http::bearerToken(request);
    dispatcher_.run(request, std::move(callback), [this, token]() {
        service_.logout(token);
        return http::noContentResponse();
    });
}

void AuthController::profile(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [](const UserRecord &user) {
            Json::Value response;
            response["user"] = http::toJson(user);
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
