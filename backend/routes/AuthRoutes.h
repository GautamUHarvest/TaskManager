#pragma once

#include <memory>

namespace taskmanager
{

class AuthController;

void registerAuthRoutes(const std::shared_ptr<AuthController> &controller);

}  // namespace taskmanager
