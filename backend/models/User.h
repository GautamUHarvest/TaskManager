#pragma once

#include <cstdint>
#include <string>

namespace taskmanager
{

struct UserRecord
{
    std::int64_t id;
    std::string employeeId;
    std::string email;
    std::string displayName;
    std::string passwordHash;
    bool active;
    bool emailVerified;
};

}  // namespace taskmanager
