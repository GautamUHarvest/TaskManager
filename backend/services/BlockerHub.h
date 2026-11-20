#pragma once

#include <drogon/WebSocketConnection.h>
#include <json/json.h>
#include <trantor/utils/TaskQueue.h>

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace taskmanager
{

class AuthService;

// Process-wide registry of live notification sockets, keyed by user id, plus
// the fan-out used to deliver blocker alerts in real time.
//
// A singleton because Drogon constructs WebSocketController instances itself,
// so there is nowhere to inject dependencies; main.cc calls configure() at
// startup to hand it the AuthService. Like security::RateLimiter, this
// state is per-process and therefore assumes a single
// backend process — the same assumption the SQLite setup already makes.
//
// Delivery is best-effort by design: a user with no live socket simply gets
// nothing pushed. The stored notification row is what guarantees they still
// see the alert, replayed when they next connect.
class BlockerHub
{
  public:
    static BlockerHub &instance();

    // Must be called once at startup, before any socket can authenticate.
    // `workers` is the shared blocking-work queue: verifying a token reads
    // SQLite, which must never run on an event-loop thread.
    void configure(AuthService *auth, trantor::TaskQueue *workers);

    // The queue token verification must be dispatched to. Null until
    // configure() has run.
    trantor::TaskQueue *workers() const;

    // Verifies an access token with the same JWT rules the REST API uses and
    // binds the socket to that user. Returns the user id, or 0 when the token
    // is invalid/expired or the hub was never configured.
    //
    // Blocking: reads SQLite. Call it from `workers()`, never from the
    // socket's event loop.
    std::int64_t authenticate(const drogon::WebSocketConnectionPtr &connection,
                              const std::string &accessToken);

    bool isAuthenticated(
        const drogon::WebSocketConnectionPtr &connection) const;

    void remove(const drogon::WebSocketConnectionPtr &connection);

    // Sends payload to every live socket belonging to userId. A user signed in
    // on two tabs gets it on both; a user with none is a no-op.
    void pushTo(std::int64_t userId, const Json::Value &payload);

  private:
    BlockerHub() = default;

    mutable std::mutex mutex_;
    std::unordered_map<std::int64_t,
                       std::vector<drogon::WebSocketConnectionPtr>>
        socketsByUser_;
    AuthService *auth_{nullptr};
    trantor::TaskQueue *workers_{nullptr};
};

}  // namespace taskmanager
