#pragma once

#include <chrono>
#include <cstddef>
#include <mutex>
#include <string>
#include <unordered_map>

namespace taskmanager::security
{

// Fixed-window request counter keyed by an arbitrary string (callers use
// "<action>:<client ip>"). Thread-safe.
//
// In-process memory only: limits reset on restart and are not shared between
// processes — the same single-process assumption as the SQLite setup.
class RateLimiter
{
  public:
    RateLimiter(std::size_t limit, std::chrono::seconds window);

    // Counts one request for `key`; throws TooManyRequestsError once `limit`
    // requests have been seen in the current window.
    void acquire(const std::string &key);

  private:
    struct Window
    {
        std::chrono::steady_clock::time_point start;
        std::size_t count{0};
    };

    // Expired windows are swept once the map grows past this many keys.
    static constexpr std::size_t kSweepThreshold = 4096;

    const std::size_t limit_;
    const std::chrono::seconds window_;
    std::mutex mutex_;
    std::unordered_map<std::string, Window> windows_;
};

}  // namespace taskmanager::security
