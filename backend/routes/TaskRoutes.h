#pragma once

#include <memory>

namespace taskmanager
{

class TaskController;

void registerTaskRoutes(const std::shared_ptr<TaskController> &controller);

}  // namespace taskmanager
