#include "Sqlite.h"

#include <utility>

namespace taskmanager::db
{

SqliteError::SqliteError(int code, const std::string &message)
    : std::runtime_error(message), code_(code)
{
}

// --- Connection -----------------------------------------------------------

Connection::Connection(const std::string &path, Mode mode)
{
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
    if (mode == Mode::ReadWriteCreate)
    {
        flags |= SQLITE_OPEN_CREATE;
    }
    const int result = sqlite3_open_v2(path.c_str(), &database_, flags, nullptr);
    if (result != SQLITE_OK)
    {
        const std::string message =
            database_ ? sqlite3_errmsg(database_) : "SQLite open failed";
        const int code =
            database_ ? sqlite3_extended_errcode(database_) : result;
        if (database_)
        {
            sqlite3_close(database_);
            database_ = nullptr;
        }
        throw SqliteError(code, message);
    }
    sqlite3_extended_result_codes(database_, 1);
    sqlite3_busy_timeout(database_, 5000);
    execute("PRAGMA foreign_keys = ON");
}

Connection::Connection(Connection &&other) noexcept
    : database_(std::exchange(other.database_, nullptr))
{
}

Connection::~Connection()
{
    if (database_)
    {
        sqlite3_close(database_);
    }
}

void Connection::execute(const std::string &sql) const
{
    char *error = nullptr;
    if (sqlite3_exec(database_, sql.c_str(), nullptr, nullptr, &error) !=
        SQLITE_OK)
    {
        const int code = sqlite3_extended_errcode(database_);
        std::string message = error ? error : sqlite3_errmsg(database_);
        sqlite3_free(error);
        throw SqliteError(code, "SQLite operation failed: " + message);
    }
}

std::int64_t Connection::lastInsertRowId() const
{
    return sqlite3_last_insert_rowid(database_);
}

int Connection::changes() const
{
    return sqlite3_changes(database_);
}

// --- Statement ------------------------------------------------------------

Statement::Statement(const Connection &connection, const std::string &sql)
    : database_(connection.get())
{
    if (sqlite3_prepare_v2(database_, sql.c_str(), -1, &statement_, nullptr) !=
        SQLITE_OK)
    {
        fail();
    }
}

Statement::~Statement()
{
    sqlite3_finalize(statement_);
}

void Statement::fail() const
{
    throw SqliteError(sqlite3_extended_errcode(database_),
                      sqlite3_errmsg(database_));
}

void Statement::bindText(int index, const std::string &value)
{
    if (sqlite3_bind_text(statement_,
                          index,
                          value.data(),
                          static_cast<int>(value.size()),
                          SQLITE_TRANSIENT) != SQLITE_OK)
    {
        fail();
    }
}

void Statement::bindInt64(int index, std::int64_t value)
{
    if (sqlite3_bind_int64(statement_, index, value) != SQLITE_OK)
    {
        fail();
    }
}

void Statement::bindNull(int index)
{
    if (sqlite3_bind_null(statement_, index) != SQLITE_OK)
    {
        fail();
    }
}

void Statement::bindOptText(int index, const std::optional<std::string> &value)
{
    value ? bindText(index, *value) : bindNull(index);
}

void Statement::bindOptInt64(int index,
                             const std::optional<std::int64_t> &value)
{
    value ? bindInt64(index, *value) : bindNull(index);
}

bool Statement::step()
{
    const int result = sqlite3_step(statement_);
    if (result == SQLITE_ROW)
    {
        return true;
    }
    if (result == SQLITE_DONE)
    {
        return false;
    }
    fail();
}

bool Statement::isNull(int index) const
{
    return sqlite3_column_type(statement_, index) == SQLITE_NULL;
}

std::int64_t Statement::int64Column(int index) const
{
    return sqlite3_column_int64(statement_, index);
}

std::string Statement::textColumn(int index) const
{
    const auto *text = sqlite3_column_text(statement_, index);
    return text ? reinterpret_cast<const char *>(text) : std::string();
}

std::optional<std::int64_t> Statement::optInt64Column(int index) const
{
    if (isNull(index))
    {
        return std::nullopt;
    }
    return int64Column(index);
}

std::optional<std::string> Statement::optTextColumn(int index) const
{
    if (isNull(index))
    {
        return std::nullopt;
    }
    return textColumn(index);
}

// --- Transaction ----------------------------------------------------------

Transaction::Transaction(const Connection &connection) : connection_(connection)
{
    connection_.execute("BEGIN IMMEDIATE");
}

Transaction::~Transaction()
{
    if (finished_)
    {
        return;
    }
    // Never throw from here: we are usually unwinding from another error,
    // and SQLite may already have rolled back by itself (e.g. after
    // SQLITE_FULL), which makes this ROLLBACK fail harmlessly.
    sqlite3_exec(connection_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
}

void Transaction::commit()
{
    connection_.execute("COMMIT");
    finished_ = true;
}

// --- Database -------------------------------------------------------------

Database::Database(std::string path) : path_(std::move(path))
{
    if (path_.empty())
    {
        throw std::invalid_argument("Database path is required");
    }
}

Connection Database::connect() const
{
    return Connection(path_);
}

}  // namespace taskmanager::db
