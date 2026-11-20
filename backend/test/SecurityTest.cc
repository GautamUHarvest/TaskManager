#include <drogon/drogon_test.h>

#include "security/AuthCrypto.h"
#include "security/OriginPolicy.h"
#include "security/RateLimiter.h"
#include "common/Errors.h"

#include <chrono>
#include <cstdlib>

DROGON_TEST(CorsOriginAllowlist)
{
    using taskmanager::security::allowedOrigins;
    using taskmanager::security::isAllowedOrigin;

    // Unset: nothing is allowed, and an empty list tells the WebSocket check
    // to skip itself.
    ::unsetenv("TASK_MANAGER_CORS_ORIGIN");
    CHECK(allowedOrigins().empty());
    CHECK(!isAllowedOrigin("http://localhost:5000"));

    // Single origin keeps working exactly as before.
    ::setenv("TASK_MANAGER_CORS_ORIGIN", "http://localhost:5000", 1);
    CHECK(isAllowedOrigin("http://localhost:5000"));
    CHECK(!isAllowedOrigin("http://192.168.0.23"));

    // Comma-separated list: laptop dev server + phone on the Pi's LAN IP.
    // Spaces, trailing slashes and empty entries are tolerated.
    ::setenv("TASK_MANAGER_CORS_ORIGIN",
             " http://localhost:5000 , http://192.168.0.23/ ,,",
             1);
    CHECK(allowedOrigins().size() == 2);
    CHECK(isAllowedOrigin("http://localhost:5000"));
    CHECK(isAllowedOrigin("http://192.168.0.23"));

    // Still exact matching: no prefix, port, scheme or empty-header leaks.
    CHECK(!isAllowedOrigin("http://192.168.0.23:8080"));
    CHECK(!isAllowedOrigin("https://192.168.0.23"));
    CHECK(!isAllowedOrigin("http://192.168.0.2"));
    CHECK(!isAllowedOrigin("http://192.168.0.23.attacker"));
    CHECK(!isAllowedOrigin(""));

    ::unsetenv("TASK_MANAGER_CORS_ORIGIN");
}

DROGON_TEST(AuthInputValidation)
{
    CHECK(taskmanager::security::validEmail("employee@uharvest.in"));
    CHECK(taskmanager::security::validEmail("EMPLOYEE@UHARVEST.IN"));
    CHECK(!taskmanager::security::validEmail("employee@example.com"));
    CHECK(!taskmanager::security::validEmail("employee@uharvest.in.attacker"));
    CHECK(taskmanager::security::validEmployeeId("EMP-001"));
    CHECK(!taskmanager::security::validEmployeeId(" EMP-001"));
    CHECK(taskmanager::security::validPassword("Good!Pass1"));
    CHECK(!taskmanager::security::validPassword("short1!"));
    CHECK(!taskmanager::security::validPassword("NoNumber!"));
}

DROGON_TEST(PasswordHashAndJwtValidation)
{
    const std::string password = "Good!Pass1";
    const auto hash = taskmanager::security::hashPassword(password);
    CHECK(taskmanager::security::verifyPassword(password, hash));
    CHECK(!taskmanager::security::verifyPassword("Wrong!Pass1", hash));

    const std::string secret(32, 's');
    const auto token = taskmanager::security::issueAccessToken(
        42, "0123456789abcdef0123456789abcdef", secret, 1000, 1600);
    const auto claims =
        taskmanager::security::verifyAccessToken(token, secret, 1100);
    REQUIRE(claims.has_value());
    CHECK(claims->userId == 42);
    CHECK(claims->sessionId == "0123456789abcdef0123456789abcdef");
    CHECK(!taskmanager::security::verifyAccessToken(token, secret, 1600));

    auto tampered = token;
    tampered[tampered.size() - 2] =
        tampered[tampered.size() - 2] == 'A' ? 'B' : 'A';
    CHECK(!taskmanager::security::verifyAccessToken(tampered, secret, 1100));
}

DROGON_TEST(RateLimiterWindow)
{
    using taskmanager::TooManyRequestsError;
    taskmanager::security::RateLimiter limiter(2, std::chrono::seconds(60));

    CHECK_NOTHROW(limiter.acquire("login:10.0.0.1"));
    CHECK_NOTHROW(limiter.acquire("login:10.0.0.1"));
    CHECK_THROWS_AS(limiter.acquire("login:10.0.0.1"), TooManyRequestsError);
    // Keys are counted independently.
    CHECK_NOTHROW(limiter.acquire("login:10.0.0.2"));

    // A zero-length window resets on every call, so it never trips.
    taskmanager::security::RateLimiter expired(1, std::chrono::seconds(0));
    CHECK_NOTHROW(expired.acquire("k"));
    CHECK_NOTHROW(expired.acquire("k"));
}
