#include "ProjectRepository.h"

#include "Rows.h"

#include <stdexcept>
#include <string>

namespace taskmanager
{

ProjectRepository::ProjectRepository(const db::Database &database)
    : database_(database)
{
}

ProjectRecord ProjectRepository::create(const NewProject &project)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "A project with that name already exists", [&] {
            db::Transaction transaction(connection);
            db::Statement insert(
                connection,
                "INSERT INTO projects (name, description, created_by_id) "
                "VALUES (?1, ?2, ?3)");
            insert.bindText(1, project.name);
            insert.bindOptText(2, project.description);
            insert.bindInt64(3, project.createdById);
            insert.step();

            auto created = rows::findById(connection,
                                          rows::kProjectColumns,
                                          "projects",
                                          connection.lastInsertRowId(),
                                          rows::project);
            if (!created)
            {
                throw std::runtime_error(
                    "Created project could not be read back");
            }
            transaction.commit();
            return *created;
        });
}

std::vector<ProjectRecord> ProjectRepository::list()
{
    auto connection = database_.connect();
    db::Statement statement(connection,
                            std::string("SELECT ") + rows::kProjectColumns +
                                " FROM projects ORDER BY name COLLATE NOCASE");
    std::vector<ProjectRecord> projects;
    while (statement.step())
    {
        projects.push_back(rows::project(statement));
    }
    return projects;
}

std::optional<ProjectRecord> ProjectRepository::find(std::int64_t id)
{
    auto connection = database_.connect();
    return rows::findById(
        connection, rows::kProjectColumns, "projects", id, rows::project);
}

}  // namespace taskmanager
