#pragma once

#include "../error_middleware/ErrorMiddleware.h"
#include "../models/User.h"
#include "../services/AuthService.h"
#include "RequestParsing.h"

#include <drogon/HttpAppFramework.h>
#include <trantor/utils/TaskQueue.h>

#include <exception>
#include <string>
#include <utility>

namespace taskmanager::http
{

// Moves request handling off the event loop. Password hashing (scrypt) and
// every SQLite call are synchronous, so controllers must never run them on a
// Drogon I/O thread; they hand a `work` callable to run() or authenticated(),
// which executes it on the shared worker queue. Whatever `work` throws is
// turned into the matching error response by ErrorMiddleware.
//
// `work` returns the drogon::HttpResponsePtr to send. It must capture by value
// whatever it needs from the request: it runs after the handler has returned.
class Dispatcher
{
  public:
    Dispatcher(AuthService &auth, trantor::TaskQueue &workers)
        : auth_(auth), workers_(workers)
    {
    }

    template <typename Work>
    void run(const drogon::HttpRequestPtr &request,
             drogon::AdviceCallback &&callback,
             Work work) const
    {
        workers_.runTaskInQueue(
            [request, work = std::move(work), callback = std::move(callback)]()
                mutable {
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

    // Like run(), for endpoints that need a signed-in caller: verifies the
    // bearer token (on the worker — it reads SQLite) and passes the caller's
    // profile to `work(const UserRecord &actor)`.
    //
    // A missing or malformed Authorization header is rejected right here, on
    // the event loop, before any work is queued.
    template <typename Work>
    void authenticated(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback,
                       Work work) const
    {
        auto token = bearerToken(request);
        run(request,
            std::move(callback),
            [&auth = auth_, token = std::move(token), work = std::move(work)]()
                mutable { return work(auth.profile(token)); });
    }

  private:
    AuthService &auth_;
    trantor::TaskQueue &workers_;
};

}  // namespace taskmanager::http
