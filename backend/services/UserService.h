#pragma once

#include "../models/User.h"
#include "../repositories/UserRepository.h"

#include <vector>

namespace taskmanager
{

// The member directory used for assignee pickers and blocker targets.
class UserService
{
  public:
    explicit UserService(UserRepository &users) : users_(users)
    {
    }

    // Active members' public profiles, ordered by display name.
    std::vector<UserRecord> allUsers()
    {
        return users_.listActive();
    }

  private:
    UserRepository &users_;
};

}  // namespace taskmanager
