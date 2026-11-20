#include "RateLimiter.h"

#include "../common/Errors.h"

#include <iterator>

namespace taskmanager::security
{

RateLimiter::RateLimiter(std::size_t limit, std::chrono::seconds window)
    : limit_(limit), window_(window)
{
}

void RateLimiter::acquire(const std::string &key)
{
    const auto now = std::chrono::steady_clock::now();
    std::lock_guard<std::mutex> lock(mutex_);
    auto &window = windows_[key];
    if (window.count == 0 || now - window.start >= window_)
    {
        window = Window{now, 0};
    }
    if (window.count >= limit_)
    {
        throw TooManyRequestsError("Too many requests");
    }
    ++window.count;

    if (windows_.size() > kSweepThreshold)
    {
        for (auto item = windows_.begin(); item != windows_.end();)
        {
            item = now - item->second.start >= window_ ? windows_.erase(item)
                                                       : std::next(item);
        }
    }
}

}  // namespace taskmanager::security
