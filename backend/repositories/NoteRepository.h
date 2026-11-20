#pragma once

#include "../db/Sqlite.h"
#include "../models/Task.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace taskmanager
{

class NoteRepository
{
  public:
    explicit NoteRepository(const db::Database &database);

    // Throws std::invalid_argument when the task does not exist.
    TaskNoteRecord add(const NewTaskNote &note);
    // Oldest first.
    std::vector<TaskNoteRecord> listForTask(std::int64_t taskId);
    std::optional<TaskNoteRecord> find(std::int64_t id);
    // Throws NotFoundError when the note does not exist.
    TaskNoteRecord update(std::int64_t id, const std::string &body);
    void remove(std::int64_t id);

  private:
    const db::Database &database_;
};

}  // namespace taskmanager
