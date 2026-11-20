#pragma once

#include <string>

namespace taskmanager::db
{

// Prepares the SQLite database for use. Call once at startup, before any
// repository runs:
//   - creates the database's parent directory if needed,
//   - restricts the database and its -wal/-shm/-journal files to the owner,
//   - switches to WAL journaling,
//   - applies every NNN_name.sql in migrationsDir not yet recorded in
//     schema_migrations, in numeric order, each in its own transaction.
void initializeDatabase(const std::string &databasePath,
                        const std::string &migrationsDir);

}  // namespace taskmanager::db
