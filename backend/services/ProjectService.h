#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/ProjectRepository.h"

#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

// Projects group tasks. A task created without project_id belongs to the
// default "Unidentified" project (id 1).
class ProjectService
{
  public:
    explicit ProjectService(ProjectRepository &projects);

    ProjectRecord addProject(const UserRecord &actor,
                             const std::string &name,
                             const std::optional<std::string> &description);
    std::vector<ProjectRecord> allProjects();

  private:
    ProjectRepository &projects_;
};

}  // namespace taskmanager
