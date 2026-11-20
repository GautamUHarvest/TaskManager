#include "BlockerSocketController.h"

#include "../security/OriginPolicy.h"
#include "../services/BlockerHub.h"

#include <drogon/HttpAppFramework.h>
#include <json/json.h>
#include <trantor/utils/Logger.h>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <string>

namespace taskmanager
{
namespace
{
// How long an anonymous socket may stay open before it must have authenticated.
constexpr double kAuthGraceSeconds = 10.0;

// Largest frame we will even try to parse. An access token is well under this;
// anything bigger is not a client of ours.
constexpr std::size_t kMaxFrameBytes = 8 * 1024;

void sendJson(const drogon::WebSocketConnectionPtr &connection,
              const Json::Value &payload)
{
    if (!connection || !connection->connected())
    {
        return;
    }
    Json::StreamWriterBuilder builder;
    builder["indentation"] = "";
    connection->send(Json::writeString(builder, payload));
}

void sendError(const drogon::WebSocketConnectionPtr &connection,
               const std::string &message)
{
    Json::Value payload;
    payload["type"] = "error";
    payload["error"] = message;
    sendJson(connection, payload);
}
}  // namespace

void BlockerSocketController::handleNewConnection(
    const drogon::HttpRequestPtr &request,
    const drogon::WebSocketConnectionPtr &connection)
{
    // CORS does not apply to WebSockets, so the Origin check has to be done
    // here or any site could open a socket against this backend. Same
    // exact-origin allowlist the HTTP routes use.
    // Unset means no allowlist is configured, so the check is skipped (same
    // as before); otherwise the Origin must match one listed entry.
    const char *allowedOrigin = std::getenv("TASK_MANAGER_CORS_ORIGIN");
    if (!security::allowedOrigins().empty() &&
        !security::isAllowedOrigin(request->getHeader("origin")))
    {
        // Logged loudly: a browser reports this as an immediate close with no
        // reason, and the mismatch is easy to hit behind nginx, where the REST
        // API is same-origin and never exercises TASK_MANAGER_CORS_ORIGIN —
        // so it can be stale or wrong without anything else noticing.
        LOG_WARN << "WebSocket rejected: Origin '"
                 << request->getHeader("origin")
                 << "' does not match TASK_MANAGER_CORS_ORIGIN '"
                 << allowedOrigin << "'";
        connection->shutdown(drogon::CloseCode::kViolation,
                            "Origin not allowed");
        return;
    }
    LOG_DEBUG << "WebSocket connected, awaiting auth frame";

    // Close the socket if it has not authenticated in time, so an anonymous
    // connection cannot be parked open indefinitely. Held weakly so a socket
    // that closes on its own is not kept alive until the timer fires.
    std::weak_ptr<drogon::WebSocketConnection> weakConnection = connection;
    drogon::app().getLoop()->runAfter(kAuthGraceSeconds, [weakConnection]() {
        const auto live = weakConnection.lock();
        if (live && live->connected() &&
            !BlockerHub::instance().isAuthenticated(live))
        {
            live->shutdown(drogon::CloseCode::kViolation,
                           "Authentication timeout");
        }
    });
}

void BlockerSocketController::handleNewMessage(
    const drogon::WebSocketConnectionPtr &connection,
    std::string &&message,
    const drogon::WebSocketMessageType &type)
{
    if (type == drogon::WebSocketMessageType::Ping ||
        type == drogon::WebSocketMessageType::Pong ||
        type == drogon::WebSocketMessageType::Close)
    {
        return;  // Handled by the protocol layer.
    }
    if (type != drogon::WebSocketMessageType::Text ||
        message.size() > kMaxFrameBytes)
    {
        connection->shutdown(drogon::CloseCode::kInvalidMessage,
                             "Unsupported frame");
        return;
    }

    Json::Value frame;
    Json::CharReaderBuilder builder;
    const std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    std::string errors;
    const bool parsed = reader->parse(
        message.data(), message.data() + message.size(), &frame, &errors);
    if (!parsed || !frame.isObject())
    {
        sendError(connection, "Expected a JSON object");
        return;
    }

    const std::string frameType =
        frame["type"].isString() ? frame["type"].asString() : std::string();

    if (frameType == "auth")
    {
        if (BlockerHub::instance().isAuthenticated(connection))
        {
            return;  // Already bound; ignore a duplicate auth.
        }
        const std::string token = frame["access_token"].isString()
                                      ? frame["access_token"].asString()
                                      : std::string();
        auto *workers = BlockerHub::instance().workers();
        if (!workers)
        {
            connection->shutdown(drogon::CloseCode::kUnexpectedCondition,
                                 "Server not ready");
            return;
        }
        // Verifying the token reads SQLite, which is synchronous — and this
        // runs on the socket's event loop, so doing it inline would stall
        // every other connection and HTTP request sharing that loop (up to
        // the 5s busy timeout if a write transaction holds the lock). Hand it
        // to the same worker queue the HTTP controllers use. send() and
        // shutdown() are thread-safe: trantor hands them to the connection's
        // own loop.
        workers->runTaskInQueue([connection, token]() {
            const std::int64_t userId =
                BlockerHub::instance().authenticate(connection, token);
            if (userId == 0)
            {
                LOG_WARN << "WebSocket auth rejected: invalid or expired "
                            "access token";
                sendError(connection, "Invalid or expired access token");
                connection->shutdown(drogon::CloseCode::kViolation,
                                     "Authentication failed");
                return;
            }
            LOG_DEBUG << "WebSocket authenticated for user " << userId;
            Json::Value ok;
            ok["type"] = "auth_ok";
            ok["user_id"] = Json::Int64(userId);
            sendJson(connection, ok);
        });
        return;
    }

    // Everything past this point requires an authenticated socket.
    if (!BlockerHub::instance().isAuthenticated(connection))
    {
        sendError(connection, "Authenticate first");
        connection->shutdown(drogon::CloseCode::kViolation,
                             "Not authenticated");
        return;
    }

    if (frameType == "ping")
    {
        Json::Value pong;
        pong["type"] = "pong";
        sendJson(connection, pong);
        return;
    }

    sendError(connection, "Unknown message type");
}

void BlockerSocketController::handleConnectionClosed(
    const drogon::WebSocketConnectionPtr &connection)
{
    BlockerHub::instance().remove(connection);
}

}  // namespace taskmanager
