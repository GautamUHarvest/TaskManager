#include "AuthRepository.h"

#include <sqlite3.h>

#include <algorithm>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <utility>
#include <vector>

namespace taskmanager
{
namespace
{
class Connection
{
  public:
    explicit Connection(const std::string &path)
    {
        const int result = sqlite3_open_v2(path.c_str(),
                                           &database_,
                                           SQLITE_OPEN_READWRITE |
                                               SQLITE_OPEN_CREATE |
                                               SQLITE_OPEN_FULLMUTEX,
                                           nullptr);
        if (result != SQLITE_OK)
        {
            const std::string message =
                database_ ? sqlite3_errmsg(database_) : "SQLite open failed";
            if (database_)
            {
                sqlite3_close(database_);
                database_ = nullptr;
            }
            throw std::runtime_error(message);
        }
        sqlite3_busy_timeout(database_, 5000);
        execute("PRAGMA foreign_keys = ON");
    }

    ~Connection()
    {
        if (database_)
        {
            sqlite3_close(database_);
        }
    }

    Connection(const Connection &) = delete;
    Connection &operator=(const Connection &) = delete;

    sqlite3 *get() const
    {
        return database_;
    } 

    void execute(const std::string &sql) const
    {
        char *error = nullptr;
        if (sqlite3_exec(database_, sql.c_str(), nullptr, nullptr, &error) !=
            SQLITE_OK)
        {
            std::string message = error ? error : sqlite3_errmsg(database_);
            sqlite3_free(error);
            throw std::runtime_error("SQLite operation failed: " + message);
        }
    }

  private:
    sqlite3 *database_{nullptr};
};

class Statement
{
  public:
    Statement(sqlite3 *database, const std::string &sql) : database_(database)
    {
        if (sqlite3_prepare_v2(database, sql.c_str(), -1, &statement_, nullptr) !=
            SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database));
        }
    }

    ~Statement()
    {
        sqlite3_finalize(statement_);
    }

    Statement(const Statement &) = delete;
    Statement &operator=(const Statement &) = delete;

    void bindText(int index, const std::string &value)
    {
        if (sqlite3_bind_text(statement_,
                              index,
                              value.data(),
                              static_cast<int>(value.size()),
                              SQLITE_TRANSIENT) != SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
    }

    void bindInt64(int index, std::int64_t value)
    {
        if (sqlite3_bind_int64(statement_, index, value) != SQLITE_OK)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
    }

    int step()
    {
        const int result = sqlite3_step(statement_);
        if (result != SQLITE_ROW && result != SQLITE_DONE)
        {
            throw std::runtime_error(sqlite3_errmsg(database_));
        }
        return result;
    }

    std::int64_t int64Column(int index) const
    {
        return sqlite3_column_int64(statement_, index);
    }

    std::string textColumn(int index) const
    {
        const auto *text = sqlite3_column_text(statement_, index);
        return text ? reinterpret_cast<const char *>(text) : std::string();
    }

  private:
    sqlite3 *database_;
    sqlite3_stmt *statement_{nullptr};
};

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

UserRecord userFromStatement(const Statement &statement)
{
    return UserRecord{statement.int64Column(0),
                      statement.textColumn(1),
                      statement.textColumn(2),
                      statement.textColumn(3),
                      statement.textColumn(4),
                      statement.int64Column(5) != 0,
                      statement.int64Column(6) != 0};
}

std::optional<UserRecord> verifiedUserForSession(Connection &connection,
                                                 const std::string &sessionId,
                                                 const std::string &refreshHash,
                                                 std::int64_t now)
{
    Statement statement(
        connection.get(),
        "SELECT u.id, u.employee_id, u.email, u.display_name, u.password_hash, "
        "u.is_active, u.email_verified_at IS NOT NULL "
        "FROM auth_sessions s JOIN users u ON u.id = s.user_id "
        "WHERE s.id = ?1 AND s.refresh_token_hash = ?2 AND s.revoked_at IS "
        "NULL AND s.expires_at > ?3 AND u.is_active = 1 AND "
        "u.email_verified_at IS NOT NULL");
    statement.bindText(1, sessionId);
    statement.bindText(2, refreshHash);
    statement.bindInt64(3, now);
    if (statement.step() == SQLITE_ROW)
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}
}  // namespace

AuthRepository::AuthRepository(std::string databasePath,
                               std::string migrationsPath)
    : databasePath_(std::move(databasePath)),
      migrationsPath_(std::move(migrationsPath))
{
    if (databasePath_.empty() || migrationsPath_.empty())
    {
        throw std::invalid_argument("Database and migration paths are required");
    }
}

void AuthRepository::initialize()
{
    const std::filesystem::path databasePath(databasePath_);
    if (databasePath.has_parent_path())
    {
        std::filesystem::create_directories(databasePath.parent_path());
    }
    for (const auto &path : {databasePath_,
                             databasePath_ + "-wal",
                             databasePath_ + "-shm",
                             databasePath_ + "-journal"})
    {
        if (std::filesystem::exists(path) &&
            chmod(path.c_str(), S_IRUSR | S_IWUSR) != 0)
        {
            throw std::runtime_error(
                "Unable to restrict SQLite database permissions");
        }
    }

    Connection connection(databasePath_);
    connection.execute("PRAGMA journal_mode = WAL");
    connection.execute(
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        "version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT "
        "(strftime('%Y-%m-%dT%H:%M:%fZ', 'now')))");

    std::vector<std::filesystem::path> migrations;
    for (const auto &entry : std::filesystem::directory_iterator(migrationsPath_))
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

    for (const auto &migration : migrations)
    {
        const int version = migrationVersion(migration);
        Statement existing(connection.get(),
                           "SELECT 1 FROM schema_migrations WHERE version = "
                           "?1");
        existing.bindInt64(1, version);
        if (existing.step() == SQLITE_ROW)
        {
            continue;
        }

        connection.execute("BEGIN IMMEDIATE");
        try
        {
            connection.execute(readFile(migration));
            Statement record(connection.get(),
                             "INSERT INTO schema_migrations(version) VALUES "
                             "(?1)");
            record.bindInt64(1, version);
            record.step();
            connection.execute("COMMIT");
        }
        catch (...)
        {
            connection.execute("ROLLBACK");
            throw;
        }
    }
}

std::int64_t AuthRepository::createUser(const std::string &employeeId,
                                        const std::string &email,
                                        const std::string &displayName,
                                        const std::string &passwordHash)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        Statement user(connection.get(),
                       "INSERT INTO users (username, employee_id, email, "
                       "display_name, password_hash, email_verified_at) "
                       "SELECT ?1, ?1, ?2, ?3, ?4, "
                       "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE "
                       "(SELECT count(*) FROM users WHERE "
                       "is_active = 1) < 25");
        user.bindText(1, employeeId);
        user.bindText(2, email);
        user.bindText(3, displayName);
        user.bindText(4, passwordHash);

        user.step();
        if (sqlite3_changes(connection.get()) != 1)
        {
            throw UserLimitError("The maximum of 25 active users is reached");
        }
        const std::int64_t userId = sqlite3_last_insert_rowid(connection.get());

        connection.execute("COMMIT");
        return userId;
    }
    catch (...)
    {
        const int errorCode = sqlite3_extended_errcode(connection.get());
        connection.execute("ROLLBACK");
        if ((errorCode & 0xff) == SQLITE_CONSTRAINT)
        {
            throw DuplicateUserError("Employee ID or email already exists");
        }
        throw;
    }
}

std::optional<UserRecord> AuthRepository::findUserByLogin(
    const std::string &login)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, employee_id, email, display_name, password_hash, "
        "is_active, email_verified_at IS NOT NULL FROM "
        "users WHERE employee_id = ?1 COLLATE NOCASE OR email = ?1 COLLATE "
        "NOCASE LIMIT 1");
    statement.bindText(1, login);
    if (statement.step() == SQLITE_ROW)
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}

std::optional<UserRecord> AuthRepository::findVerifiedUserById(
    std::int64_t userId)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "SELECT id, employee_id, email, display_name, password_hash, "
        "is_active, email_verified_at IS NOT NULL FROM "
        "users WHERE id = ?1 AND is_active = 1 AND email_verified_at IS NOT "
        "NULL");
    statement.bindInt64(1, userId);
    if (statement.step() == SQLITE_ROW)
    {
        return userFromStatement(statement);
    }
    return std::nullopt;
}

void AuthRepository::createSession(std::int64_t userId,
                                   const std::string &sessionId,
                                   const std::string &refreshHash,
                                   std::int64_t expiresAt)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "INSERT INTO auth_sessions(id, user_id, refresh_token_hash, expires_at) "
        "SELECT ?1, id, ?3, ?4 FROM users WHERE id = ?2 AND is_active = 1 "
        "AND email_verified_at IS NOT NULL");
    statement.bindText(1, sessionId);
    statement.bindInt64(2, userId);
    statement.bindText(3, refreshHash);
    statement.bindInt64(4, expiresAt);
    statement.step();
    if (sqlite3_changes(connection.get()) != 1)
    {
        throw std::runtime_error("Unable to create authentication session");
    }
}

std::optional<UserRecord> AuthRepository::rotateSession(
    const std::string &sessionId,
    const std::string &oldRefreshHash,
    const std::string &newRefreshHash,
    std::int64_t now,
    std::int64_t newExpiresAt)
{
    Connection connection(databasePath_);
    connection.execute("BEGIN IMMEDIATE");
    try
    {
        auto user = verifiedUserForSession(
            connection, sessionId, oldRefreshHash, now);
        if (!user)
        {
            connection.execute("ROLLBACK");
            return std::nullopt;
        }
        Statement update(
            connection.get(),
            "UPDATE auth_sessions SET refresh_token_hash = ?1, expires_at = "
            "?2 WHERE id = ?3 AND refresh_token_hash = ?4 AND revoked_at IS "
            "NULL AND expires_at > ?5");
        update.bindText(1, newRefreshHash);
        update.bindInt64(2, newExpiresAt);
        update.bindText(3, sessionId);
        update.bindText(4, oldRefreshHash);
        update.bindInt64(5, now);
        update.step();
        if (sqlite3_changes(connection.get()) != 1)
        {
            connection.execute("ROLLBACK");
            return std::nullopt;
        }
        connection.execute("COMMIT");
        return user;
    }
    catch (...)
    {
        connection.execute("ROLLBACK");
        throw;
    }
}

bool AuthRepository::revokeSession(const std::string &sessionId,
                                   std::int64_t userId)
{
    Connection connection(databasePath_);
    Statement statement(
        connection.get(),
        "UPDATE auth_sessions SET revoked_at = unixepoch() WHERE id = ?1 AND "
        "user_id = ?2 AND revoked_at IS NULL");
    statement.bindText(1, sessionId);
    statement.bindInt64(2, userId);
    statement.step();
    return sqlite3_changes(connection.get()) == 1;
}

}  // namespace taskmanager
