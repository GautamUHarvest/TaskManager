#include "Migrations.h"

#include "Sqlite.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <sys/stat.h>
#include <vector>

namespace taskmanager::db
{
namespace
{
std::string readFile(const std::filesystem::path &path)
{
    std::ifstream input(path);
    if (!input)
    {
        throw std::runtime_error("Unable to read database migration: " +
                                 path.string());
    }
    std::ostringstream content;
    content << input.rdbuf();
    return content.str();
}

int migrationVersion(const std::filesystem::path &path)
{
    const std::string name = path.filename().string();
    const auto separator = name.find('_');
    if (separator == std::string::npos || separator == 0)
    {
        throw std::runtime_error("Invalid migration filename: " + name);
    }
    try
    {
        return std::stoi(name.substr(0, separator));
    }
    catch (const std::exception &)
    {
        throw std::runtime_error("Invalid migration filename: " + name);
    }
}

void restrictPermissions(const std::string &databasePath)
{
    const std::filesystem::path path(databasePath);
    if (path.has_parent_path())
    {
        std::filesystem::create_directories(path.parent_path());
    }
    for (const auto &file : {databasePath,
                             databasePath + "-wal",
                             databasePath + "-shm",
                             databasePath + "-journal"})
    {
        if (std::filesystem::exists(file) &&
            chmod(file.c_str(), S_IRUSR | S_IWUSR) != 0)
        {
            throw std::runtime_error(
                "Unable to restrict SQLite database permissions");
        }
    }
}

std::vector<std::filesystem::path> sortedMigrations(const std::string &migrationsDir)
{
    std::vector<std::filesystem::path> migrations;
    for (const auto &entry : std::filesystem::directory_iterator(migrationsDir))
    {
        if (entry.is_regular_file() && entry.path().extension() == ".sql")
        {
            migrations.push_back(entry.path());
        }
    }
    std::sort(migrations.begin(),
              migrations.end(),
              [](const auto &left, const auto &right) {
                  return migrationVersion(left) < migrationVersion(right);
              });
    return migrations;
}
}  // namespace

void initializeDatabase(const std::string &databasePath,
                        const std::string &migrationsDir)
{
    if (databasePath.empty() || migrationsDir.empty())
    {
        throw std::invalid_argument("Database and migration paths are required");
    }
    restrictPermissions(databasePath);

    Connection connection(databasePath, Connection::Mode::ReadWriteCreate);
    connection.execute("PRAGMA journal_mode = WAL");
    connection.execute(
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        "version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT "
        "(strftime('%Y-%m-%dT%H:%M:%fZ', 'now')))");

    for (const auto &migration : sortedMigrations(migrationsDir))
    {
        const int version = migrationVersion(migration);
        {
            Statement existing(
                connection, "SELECT 1 FROM schema_migrations WHERE version = ?1");
            existing.bindInt64(1, version);
            if (existing.step())
            {
                continue;
            }
        }

        Transaction transaction(connection);
        connection.execute(readFile(migration));
        Statement record(connection,
                         "INSERT INTO schema_migrations(version) VALUES (?1)");
        record.bindInt64(1, version);
        record.step();
        transaction.commit();
    }
}

}  // namespace taskmanager::db
