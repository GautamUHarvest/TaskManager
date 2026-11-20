#pragma once

#include <sqlite3.h>

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>

// Thin RAII wrappers over the raw sqlite3 C API, shared by every repository.
//
// Repositories open a short-lived Connection per operation (SQLite opens are
// cheap, and it keeps each worker thread on its own handle). Every failing
// SQLite call throws SqliteError carrying the extended result code captured
// at the moment of failure — callers must not query sqlite3_errcode() later,
// because once any other call has run on the handle that value is undefined.
namespace taskmanager::db
{

class SqliteError : public std::runtime_error
{
  public:
    SqliteError(int code, const std::string &message);

    // Extended result code, e.g. SQLITE_CONSTRAINT_FOREIGNKEY.
    int code() const noexcept
    {
        return code_;
    }

    // True for any constraint failure: UNIQUE, NOT NULL, CHECK, FOREIGN KEY,
    // or a trigger's RAISE(ABORT, ...).
    bool isConstraint() const noexcept
    {
        return (code_ & 0xff) == SQLITE_CONSTRAINT;
    }

  private:
    int code_;
};

class Connection
{
  public:
    enum class Mode
    {
        // Normal operation: the database must already exist.
        ReadWrite,
        // Startup only: create the file if it is missing.
        ReadWriteCreate
    };

    // Opens the database with a 5s busy timeout and foreign keys enforced.
    explicit Connection(const std::string &path, Mode mode = Mode::ReadWrite);
    ~Connection();

    Connection(const Connection &) = delete;
    Connection &operator=(const Connection &) = delete;
    Connection(Connection &&other) noexcept;
    Connection &operator=(Connection &&) = delete;

    sqlite3 *get() const
    {
        return database_;
    }

    // Runs one or more SQL statements that return no rows.
    void execute(const std::string &sql) const;

    std::int64_t lastInsertRowId() const;
    // Rows changed by the most recent INSERT/UPDATE/DELETE.
    int changes() const;

  private:
    sqlite3 *database_{nullptr};
};

class Statement
{
  public:
    Statement(const Connection &connection, const std::string &sql);
    ~Statement();

    Statement(const Statement &) = delete;
    Statement &operator=(const Statement &) = delete;

    void bindText(int index, const std::string &value);
    void bindInt64(int index, std::int64_t value);
    void bindNull(int index);
    void bindOptText(int index, const std::optional<std::string> &value);
    void bindOptInt64(int index, const std::optional<std::int64_t> &value);

    // Advances the statement. Returns true when a row is available and false
    // when the statement has finished; throws SqliteError on failure.
    bool step();

    bool isNull(int index) const;
    std::int64_t int64Column(int index) const;
    std::string textColumn(int index) const;
    std::optional<std::int64_t> optInt64Column(int index) const;
    std::optional<std::string> optTextColumn(int index) const;

  private:
    [[noreturn]] void fail() const;

    sqlite3 *database_;
    sqlite3_stmt *statement_{nullptr};
};

// BEGIN IMMEDIATE on construction; ROLLBACK on destruction unless commit()
// ran. Rolling back from the destructor means an exception anywhere in the
// transaction body can never leave it open — and a failing ROLLBACK (SQLite
// may already have rolled back on its own) can never replace the exception
// that caused it.
class Transaction
{
  public:
    explicit Transaction(const Connection &connection);
    ~Transaction();

    Transaction(const Transaction &) = delete;
    Transaction &operator=(const Transaction &) = delete;

    void commit();

  private:
    const Connection &connection_;
    bool finished_{false};
};

// Where the database lives. Repositories hold one of these and call connect()
// per operation, so connection policy (pooling, pragmas) has a single owner.
class Database
{
  public:
    explicit Database(std::string path);

    const std::string &path() const
    {
        return path_;
    }

    Connection connect() const;

  private:
    std::string path_;
};

// Runs `work` and turns a constraint failure into std::invalid_argument with
// `message` (HTTP 400). Any other error propagates unchanged. Typical use is a
// whole transaction, so the rollback has already happened by the time the
// message is thrown:
//
//     return db::mapConstraintError("Invalid note", [&] { ... });
template <typename Work>
auto mapConstraintError(const char *message, Work &&work) -> decltype(work())
{
    try
    {
        return work();
    }
    catch (const SqliteError &error)
    {
        if (error.isConstraint())
        {
            throw std::invalid_argument(message);
        }
        throw;
    }
}

}  // namespace taskmanager::db
