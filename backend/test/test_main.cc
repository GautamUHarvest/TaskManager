// Test runner entry point. The test cases live in the other *.cc files in
// this directory (SecurityTest, TaskRulesTest, RepositoryTest); this file only
// starts Drogon's event loop around them.
#define DROGON_TEST_MAIN
#include <drogon/drogon_test.h>
#include <drogon/drogon.h>

#include <future>
#include <thread>

int main(int argc, char **argv)
{
    using namespace drogon;

    std::promise<void> started;
    std::future<void> ready = started.get_future();

    // Start the main loop on another thread.
    std::thread loop([&]() {
        // Fulfilled once the loop is running.
        app().getLoop()->queueInLoop([&started]() { started.set_value(); });
        app().run();
    });

    ready.get();
    const int status = test::run(argc, argv);

    // Ask the event loop to shut down and wait.
    app().getLoop()->queueInLoop([]() { app().quit(); });
    loop.join();
    return status;
}
