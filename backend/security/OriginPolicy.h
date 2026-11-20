#pragma once

#include <cstdlib>
#include <string>
#include <vector>

// Header-only on purpose: sources are gathered with aux_source_directory,
// which only rescans at configure time, so a new .cc here would silently be
// left out of the link until someone re-ran cmake.
namespace taskmanager::security
{

// Origins allowed by TASK_MANAGER_CORS_ORIGIN, a comma-separated list of exact
// origins, e.g. "http://localhost:5000,http://192.168.0.23". Entries are
// trimmed and a trailing '/' is dropped (an Origin header never has one, but
// it is an easy thing to type into an env var). Empty when unset.
inline std::vector<std::string> allowedOrigins()
{
    std::vector<std::string> origins;
    const char *raw = std::getenv("TASK_MANAGER_CORS_ORIGIN");
    if (!raw)
    {
        return origins;
    }
    const std::string text(raw);
    std::size_t start = 0;
    while (start <= text.size())
    {
        auto end = text.find(',', start);
        if (end == std::string::npos)
        {
            end = text.size();
        }
        std::string entry = text.substr(start, end - start);
        const auto first = entry.find_first_not_of(" \t");
        const auto last = entry.find_last_not_of(" \t");
        entry = first == std::string::npos
                    ? std::string()
                    : entry.substr(first, last - first + 1);
        while (!entry.empty() && entry.back() == '/')
        {
            entry.pop_back();
        }
        if (!entry.empty())
        {
            origins.push_back(entry);
        }
        start = end + 1;
    }
    return origins;
}

// True when origin exactly matches one configured origin. An empty or
// missing Origin header never matches.
inline bool isAllowedOrigin(const std::string &origin)
{
    if (origin.empty())
    {
        return false;
    }
    for (const auto &allowed : allowedOrigins())
    {
        if (origin == allowed)
        {
            return true;
        }
    }
    return false;
}

}  // namespace taskmanager::security
