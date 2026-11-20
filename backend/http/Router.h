#pragma once

#include <drogon/HttpAppFramework.h>

#include <map>
#include <memory>
#include <set>
#include <string>
#include <utility>

namespace taskmanager::http
{

// Registers API routes with Drogon and remembers each path's methods, so CORS
// preflight is answered from the same table the routes were registered from
// — there is no second list of paths to keep in sync.
//
// Every route runs behind ErrorMiddleware, which normalizes error bodies and
// adds CORS headers for allowed origins.
//
//     Router router(drogon::app());
//     router.post("/api/task/add", tasks, &TaskController::addTask);
//     router.installCorsPreflight();
class Router
{
  public:
    explicit Router(drogon::HttpAppFramework &app);

    template <typename Controller>
    void get(const std::string &path,
             std::shared_ptr<Controller> controller,
             void (Controller::*handler)(const drogon::HttpRequestPtr &,
                                         drogon::AdviceCallback &&))
    {
        add(path, drogon::Get, std::move(controller), handler);
    }

    template <typename Controller>
    void post(const std::string &path,
              std::shared_ptr<Controller> controller,
              void (Controller::*handler)(const drogon::HttpRequestPtr &,
                                          drogon::AdviceCallback &&))
    {
        add(path, drogon::Post, std::move(controller), handler);
    }

    // Installs one sync advice that answers OPTIONS for every registered
    // path. Call once, after all routes are added. OPTIONS for an unknown
    // path falls through to the default 404 handler.
    void installCorsPreflight();

  private:
    template <typename Controller>
    void add(const std::string &path,
             drogon::HttpMethod method,
             std::shared_ptr<Controller> controller,
             void (Controller::*handler)(const drogon::HttpRequestPtr &,
                                         drogon::AdviceCallback &&))
    {
        record(path, method);
        app_.registerHandler(
            path,
            [controller = std::move(controller), handler](
                const drogon::HttpRequestPtr &request,
                drogon::AdviceCallback &&callback) {
                ((*controller).*handler)(request, std::move(callback));
            },
            {method, "taskmanager::ErrorMiddleware"});
    }

    void record(const std::string &path, drogon::HttpMethod method);

    drogon::HttpAppFramework &app_;
    // path -> allowed method names ("GET", "POST"). Filled before the server
    // starts and read-only afterwards, so the advice needs no locking.
    std::shared_ptr<std::map<std::string, std::set<std::string>>> methods_;
};

}  // namespace taskmanager::http
