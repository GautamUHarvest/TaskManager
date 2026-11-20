#pragma once

#include <algorithm>
#include <cctype>
#include <string>

// Small string helpers shared by the auth and task services. Header-only: they
// are a few lines each and used on hot validation paths.
namespace taskmanager::text
{

// Strips leading and trailing whitespace (space, \t, \n, \v, \f, \r).
inline std::string trim(const std::string &value)
{
    const auto isSpace = [](unsigned char c) { return std::isspace(c) != 0; };
    const auto first = std::find_if_not(value.begin(), value.end(), isSpace);
    const auto last =
        std::find_if_not(value.rbegin(), value.rend(), isSpace).base();
    return first < last ? std::string(first, last) : std::string();
}

inline std::string lowercase(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

}  // namespace taskmanager::text
