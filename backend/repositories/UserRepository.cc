#include "UserRepository.h"

#include "Rows.h"

#include <string>

namespace taskmanager
{

UserRepository::UserRepository(const db::Database &database)
    : database_(database)
{
}

std::vector<UserRecord> UserRepository::listActive()
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        std::string("SELECT ") + rows::kUserSummaryColumns +
            " FROM users WHERE is_active = 1 "
            "ORDER BY display_name COLLATE NOCASE");
    std::vector<UserRecord> users;
    while (statement.step())
    {
        users.push_back(rows::userSummary(statement));
    }
    return users;
}

std::optional<UserRecord> UserRepository::findActive(std::int64_t id)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        std::string("SELECT ") + rows::kUserSummaryColumns +
            " FROM users WHERE id = ?1 AND is_active = 1");
    statement.bindInt64(1, id);
    if (!statement.step())
    {
        return std::nullopt;
    }
    return rows::userSummary(statement);
}

}  // namespace taskmanager
