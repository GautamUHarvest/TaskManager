#include "NoteRepository.h"

#include "../common/Errors.h"
#include "Rows.h"

#include <stdexcept>

namespace taskmanager
{

NoteRepository::NoteRepository(const db::Database &database)
    : database_(database)
{
}

TaskNoteRecord NoteRepository::add(const NewTaskNote &note)
{
    auto connection = database_.connect();
    return db::mapConstraintError("Invalid note: the task does not exist", [&] {
        db::Transaction transaction(connection);
        db::Statement insert(connection,
                             "INSERT INTO task_notes (task_id, author_id, body) "
                             "VALUES (?1, ?2, ?3)");
        insert.bindInt64(1, note.taskId);
        insert.bindInt64(2, note.authorId);
        insert.bindText(3, note.body);
        insert.step();

        auto created = rows::findById(connection,
                                      rows::kNoteColumns,
                                      "task_notes",
                                      connection.lastInsertRowId(),
                                      rows::note);
        if (!created)
        {
            throw std::runtime_error("Created note could not be read back");
        }
        transaction.commit();
        return *created;
    });
}

std::vector<TaskNoteRecord> NoteRepository::listForTask(std::int64_t taskId)
{
    auto connection = database_.connect();
    db::Statement statement(connection,
                            std::string("SELECT ") + rows::kNoteColumns +
                                " FROM task_notes WHERE task_id = ?1 "
                                "ORDER BY created_at, id");
    statement.bindInt64(1, taskId);
    std::vector<TaskNoteRecord> notes;
    while (statement.step())
    {
        notes.push_back(rows::note(statement));
    }
    return notes;
}

std::optional<TaskNoteRecord> NoteRepository::find(std::int64_t id)
{
    auto connection = database_.connect();
    return rows::findById(
        connection, rows::kNoteColumns, "task_notes", id, rows::note);
}

TaskNoteRecord NoteRepository::update(std::int64_t id, const std::string &body)
{
    auto connection = database_.connect();
    return db::mapConstraintError("Invalid note: the body is empty", [&] {
        db::Transaction transaction(connection);
        db::Statement update(
            connection,
            "UPDATE task_notes SET body = ?1, "
            "updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?2");
        update.bindText(1, body);
        update.bindInt64(2, id);
        update.step();

        auto updated = rows::findById(
            connection, rows::kNoteColumns, "task_notes", id, rows::note);
        if (!updated)
        {
            throw NotFoundError("Note not found");
        }
        transaction.commit();
        return *updated;
    });
}

void NoteRepository::remove(std::int64_t id)
{
    auto connection = database_.connect();
    db::Statement statement(connection, "DELETE FROM task_notes WHERE id = ?1");
    statement.bindInt64(1, id);
    statement.step();
}

}  // namespace taskmanager
