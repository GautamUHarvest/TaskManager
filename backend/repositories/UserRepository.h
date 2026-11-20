#pragma once

#include "../db/Sqlite.h"
#include "../models/User.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace taskmanager
{

// Read-only member directory for the task domain. Returns public profiles
// only: passwordHash is always empty. Account writes live in AuthRepository.
class UserRepository
{
  public:
    explicit UserRepository(const db::Database &database);

    // Active members, ordered by display name (case-insensitive).
    std::vector<UserRecord> listActive();
    std::optional<UserRecord> findActive(std::int64_t id);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
