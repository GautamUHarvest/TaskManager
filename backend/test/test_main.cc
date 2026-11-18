#define DROGON_TEST_MAIN
#include <drogon/drogon_test.h>
#include <drogon/drogon.h>

#include "../security/AuthCrypto.h"

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

int main(int argc, char** argv) 
{
    using namespace drogon;

    std::promise<void> p1;
    std::future<void> f1 = p1.get_future();

    // Start the main loop on another thread
    std::thread thr([&]() {
        // Queues the promise to be fulfilled after starting the loop
        app().getLoop()->queueInLoop([&p1]() { p1.set_value(); });
        app().run();
    });

    // The future is only satisfied after the event loop started
    f1.get();
    int status = test::run(argc, argv);

    // Ask the event loop to shutdown and wait
    app().getLoop()->queueInLoop([]() { app().quit(); });
    thr.join();
    return status;
}