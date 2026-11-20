#pragma once

#include "../http/Dispatcher.h"
#include "../services/NoteService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/task/note, /api/task/note/update, /api/task/note/delete.
class NoteController
{
  public:
    NoteController(NoteService &service, const http::Dispatcher &dispatcher);

    void addNote(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void updateNote(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void deleteNote(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);

  private:
    NoteService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
