#include "BlockerHub.h"

#include "AuthService.h"

#include <algorithm>
#include <memory>

namespace taskmanager
{
namespace
{
std::string serialize(const Json::Value &payload)
{
    Json::StreamWriterBuilder builder;
    // Compact: these frames are machine-read, never eyeballed.
    builder["indentation"] = "";
    return Json::writeString(builder, payload);
}
}  // namespace

BlockerHub &BlockerHub::instance()
{
    static BlockerHub hub;
    return hub;
}

void BlockerHub::configure(AuthService *auth, trantor::TaskQueue *workers)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auth_ = auth;
    workers_ = workers;
}

trantor::TaskQueue *BlockerHub::workers() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return workers_;
}

std::int64_t BlockerHub::authenticate(
    const drogon::WebSocketConnectionPtr &connection,
    const std::string &accessToken)
{
    AuthService *auth = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auth = auth_;
    }
    if (!auth || !connection)
    {
        return 0;
    }

    // profile() throws UnauthorizedError on a bad or expired token. A socket
    // is not an HTTP request, so there is no ErrorMiddleware to catch it —
    // swallow it here and report failure to the caller, which closes the
    // socket.
    std::int64_t userId = 0;
    try
    {
        userId = auth->profile(accessToken).id;
    }
    catch (const std::exception &)
    {
        return 0;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto &sockets = socketsByUser_[userId];
    if (std::find(sockets.begin(), sockets.end(), connection) == sockets.end())
    {
        sockets.push_back(connection);
    }
    return userId;
}

bool BlockerHub::isAuthenticated(
    const drogon::WebSocketConnectionPtr &connection) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto &entry : socketsByUser_)
    {
        if (std::find(entry.second.begin(), entry.second.end(), connection) !=
            entry.second.end())
        {
            return true;
        }
    }
    return false;
}

void BlockerHub::remove(const drogon::WebSocketConnectionPtr &connection)
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto entry = socketsByUser_.begin(); entry != socketsByUser_.end();)
    {
        auto &sockets = entry->second;
        sockets.erase(std::remove(sockets.begin(), sockets.end(), connection),
                      sockets.end());
        // Drop the user's bucket once their last socket goes, so the map does
        // not grow one empty vector per user who has ever connected.
        entry = sockets.empty() ? socketsByUser_.erase(entry)
                                : std::next(entry);
    }
}

void BlockerHub::pushTo(std::int64_t userId, const Json::Value &payload)
{
    std::vector<drogon::WebSocketConnectionPtr> targets;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto entry = socketsByUser_.find(userId);
        if (entry == socketsByUser_.end())
        {
            return;
        }
        targets = entry->second;
    }

    // Send outside the lock: send() touches the connection's event loop, and
    // holding the hub mutex across that would serialise every push behind the
    // slowest socket.
    const std::string frame = serialize(payload);
    for (const auto &connection : targets)
    {
        if (connection && connection->connected())
        {
            connection->send(frame);
        }
    }
}

}  // namespace taskmanager
