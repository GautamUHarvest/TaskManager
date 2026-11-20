#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace taskmanager
{

class ProjectRepository
{
  public:
    explicit ProjectRepository(const db::Database &database);

    // Throws std::invalid_argument when the name is taken (case-insensitive).
    ProjectRecord create(const NewProject &project);
    // Ordered by name (case-insensitive).
    std::vector<ProjectRecord> list();
    std::optional<ProjectRecord> find(std::int64_t id);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
