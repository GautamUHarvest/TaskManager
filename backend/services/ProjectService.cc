#include "ProjectService.h"

#include "../common/Text.h"
#include "TaskRules.h"

#include <stdexcept>

namespace taskmanager
{

ProjectService::ProjectService(ProjectRepository &projects)
    : projects_(projects)
{
}

ProjectRecord ProjectService::addProject(
    const UserRecord &actor,
    const std::string &name,
    const std::optional<std::string> &description)
{
    const std::string trimmedName = text::trim(name);
    if (trimmedName.empty())
    {
        throw std::invalid_argument("Field 'name' is required");
    }
    if (trimmedName.size() > 120)
    {
        throw std::invalid_argument("Field 'name' must be 1 to 120 characters");
    }

    NewProject project;
    project.createdById = actor.id;
    project.name = trimmedName;
    project.description =
        rules::normalizeOptionalText(description, 4000, "description");
    return projects_.create(project);
}

std::vector<ProjectRecord> ProjectService::allProjects()
{
    return projects_.list();
}

}  // namespace taskmanager
