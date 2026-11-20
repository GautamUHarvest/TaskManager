#include "NoteService.h"

#include "../common/Errors.h"
#include "TaskRules.h"

namespace taskmanager
{

NoteService::NoteService(NoteRepository &notes) : notes_(notes)
{
}

TaskNoteRecord NoteService::requireOwnNote(const UserRecord &actor,
                                           std::int64_t noteId,
                                           const char *forbiddenMessage)
{
    rules::requirePositiveId(noteId, "note_id");
    auto note = notes_.find(noteId);
    if (!note)
    {
        throw NotFoundError("Note not found");
    }
    if (note->authorId != actor.id)
    {
        throw ForbiddenError(forbiddenMessage);
    }
    return *note;
}

TaskNoteRecord NoteService::addNote(const UserRecord &actor,
                                    std::int64_t taskId,
                                    const std::string &body)
{
    rules::requirePositiveId(taskId, "task_id");
    NewTaskNote note;
    note.taskId = taskId;
    note.authorId = actor.id;
    note.body = rules::normalizeBody(body);
    return notes_.add(note);
}

TaskNoteRecord NoteService::editNote(const UserRecord &actor,
                                     std::int64_t noteId,
                                     const std::string &body)
{
    requireOwnNote(actor, noteId, "Only the note's author can edit it");
    return notes_.update(noteId, rules::normalizeBody(body));
}

void NoteService::deleteNote(const UserRecord &actor, std::int64_t noteId)
{
    requireOwnNote(actor, noteId, "Only the note's author can delete it");
    notes_.remove(noteId);
}

}  // namespace taskmanager
