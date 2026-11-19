#pragma once

#include <drogon/WebSocketController.h>

namespace taskmanager
{

// Real-time channel for blocker alerts, at ws(s)://<host>/ws/notifications.
//
// A browser cannot set an Authorization header on a WebSocket handshake, and
// putting the bearer token in the query string would write it into nginx and
// Drogon access logs — which backend/README.md explicitly forbids. So the
// socket authenticates with its FIRST message instead:
//
//     client -> {"type":"auth","access_token":"<jwt>"}
//     server -> {"type":"auth_ok","user_id":3}
//
// Until that succeeds the connection is anonymous and is dropped after a short
// grace period. Afterwards the server only pushes; the client's only other
// verb is {"type":"ping"}, answered with {"type":"pong"} so idle proxies do
// not reap the connection.
//
// This is the one place the backend uses a Drogon auto-registering controller
// rather than the manual app().registerHandler wiring used everywhere else —
// Drogon offers no non-macro equivalent for WebSocket routes.
class BlockerSocketController
    : public drogon::WebSocketController<BlockerSocketController>
{
  public:
    void handleNewMessage(const drogon::WebSocketConnectionPtr &connection,
                          std::string &&message,
                          const drogon::WebSocketMessageType &type) override;
    void handleNewConnection(
        const drogon::HttpRequestPtr &request,
        const drogon::WebSocketConnectionPtr &connection) override;
    void handleConnectionClosed(
        const drogon::WebSocketConnectionPtr &connection) override;

    WS_PATH_LIST_BEGIN
    WS_PATH_ADD("/ws/notifications");
    WS_PATH_LIST_END
};

}  // namespace taskmanager
