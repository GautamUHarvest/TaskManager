#pragma once

#include "../models/Task.h"
#include "../models/User.h"
#include "../repositories/NoteRepository.h"

#include <cstdint>
#include <string>

namespace taskmanager
{

// Free-text task notes. Any member may add one; only its author may edit or
// delete it (ForbiddenError otherwise).
class NoteService
{
  public:
    explicit NoteService(NoteRepository &notes);

    TaskNoteRecord addNote(const UserRecord &actor,
                           std::int64_t taskId,
                           const std::string &body);
    TaskNoteRecord editNote(const UserRecord &actor,
                            std::int64_t noteId,
                            const std::string &body);
    void deleteNote(const UserRecord &actor, std::int64_t noteId);

  private:
    // The note if `actor` wrote it; NotFoundError / ForbiddenError otherwise.
    TaskNoteRecord requireOwnNote(const UserRecord &actor,
                                  std::int64_t noteId,
                                  const char *forbiddenMessage);

    NoteRepository &notes_;
};

}  // namespace taskmanager
