#include "NoteController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"

#include <utility>

namespace taskmanager
{
using namespace http;

NoteController::NoteController(NoteService &service,
                               const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void NoteController::addNote(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto created = service_.addNote(
                actor, requiredInt64(body, "task_id"), requiredString(body, "body"));
            Json::Value response;
            response["message"] = "Note created";
            response["note"] = toJson(created);
            return jsonResponse(drogon::k201Created, response);
        });
}

void NoteController::updateNote(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto updated = service_.editNote(
                actor, requiredInt64(body, "note_id"), requiredString(body, "body"));
            Json::Value response;
            response["message"] = "Note updated";
            response["note"] = toJson(updated);
            return jsonResponse(drogon::k200OK, response);
        });
}

void NoteController::deleteNote(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto noteId = requiredInt64(requiredBody(request), "note_id");
            service_.deleteNote(actor, noteId);
            Json::Value response;
            response["message"] = "Note deleted";
            response["deleted_note_id"] = Json::Int64(noteId);
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
