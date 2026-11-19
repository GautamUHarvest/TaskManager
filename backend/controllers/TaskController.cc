#include "TaskController.h"

#include "../error_middleware/ErrorMiddleware.h"
#include "../services/AuthService.h"

#include <algorithm>
#include <cctype>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace taskmanager
{
namespace
{
// Mirrors the helpers in AuthController.cc; shared request/JSON utilities are
// part of the planned modularity pass.
std::string bearerToken(const drogon::HttpRequestPtr &request)
{
    const auto &authorization = request->getHeader("authorization");
    if (authorization.size() <= 7)
    {
        throw UnauthorizedError("A bearer access token is required");
    }

    std::string scheme = authorization.substr(0, 7);
    std::transform(scheme.begin(),
                   scheme.end(),
                   scheme.begin(),
                   [](unsigned char character) {
                       return static_cast<char>(std::tolower(character));
                   });
    if (scheme != "bearer ")
    {
        throw UnauthorizedError("A bearer access token is required");
    }
    return authorization.substr(7);
}

Json::Value requiredBody(const drogon::HttpRequestPtr &request)
{
    const auto &body = request->getJsonObject();
    if (!body || !body->isObject())
    {
        throw std::invalid_argument("A JSON request body is required");
    }
    return *body;
}

std::string requiredString(const Json::Value &body, const char *field)
{
    if (!body.isMember(field) || !body[field].isString() ||
        body[field].asString().empty())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' is required");
    }
    return body[field].asString();
}

std::optional<std::string> optionalString(const Json::Value &body,
                                          const char *field)
{
    if (!body.isMember(field) || body[field].isNull())
    {
        return std::nullopt;
    }
    if (!body[field].isString())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be a string");
    }
    return body[field].asString();
}

std::int64_t requiredInt64(const Json::Value &body, const char *field)
{
    if (!body.isMember(field) || body[field].isNull() ||
        !body[field].isIntegral())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' is required and must be an integer");
    }
    return body[field].asInt64();
}

// Parses a required positive-integer query parameter (e.g. ?task_id=12).
std::int64_t requiredIdParam(const std::string &value, const char *field)
{
    if (value.empty())
    {
        throw std::invalid_argument(std::string("Query parameter '") + field +
                                    "' is required");
    }
    std::int64_t parsed = 0;
    try
    {
        std::size_t pos = 0;
        parsed = std::stoll(value, &pos);
        if (pos != value.size())
        {
            throw std::invalid_argument("trailing characters");
        }
    }
    catch (const std::exception &)
    {
        throw std::invalid_argument(std::string("Query parameter '") + field +
                                    "' must be an integer");
    }
    if (parsed <= 0)
    {
        throw std::invalid_argument(std::string("Query parameter '") + field +
                                    "' must be a positive id");
    }
    return parsed;
}

std::optional<std::int64_t> optionalInt64(const Json::Value &body,
                                         const char *field)
{
    if (!body.isMember(field) || body[field].isNull())
    {
        return std::nullopt;
    }
    if (!body[field].isIntegral())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be an integer");
    }
    return body[field].asInt64();
}

// Parses an optional array of integers (e.g. "assignee_ids": [1, 2]). A missing
// or null field yields an empty list. Also accepts a single integer for
// convenience.
std::vector<std::int64_t> optionalInt64Array(const Json::Value &body,
                                             const char *field)
{
    std::vector<std::int64_t> result;
    if (!body.isMember(field) || body[field].isNull())
    {
        return result;
    }
    const auto &value = body[field];
    if (value.isIntegral())
    {
        result.push_back(value.asInt64());
        return result;
    }
    if (!value.isArray())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be an array of integers");
    }
    for (const auto &element : value)
    {
        if (!element.isIntegral())
        {
            throw std::invalid_argument(std::string("Field '") + field +
                                        "' must contain only integers");
        }
        result.push_back(element.asInt64());
    }
    return result;
}

// --- Partial-update (PATCH-style) readers --------------------------------
// The optional* helpers above collapse "key absent" and "key present but
// null" into a single nullopt, which is right for create but wrong for edit:
// on an edit an absent key means "leave this column alone" while an explicit
// null means "clear it". These return an engaged outer optional only when the
// key is actually present in the body.

std::optional<std::string> patchString(const Json::Value &body,
                                       const char *field)
{
    if (!body.isMember(field))
    {
        return std::nullopt;
    }
    if (!body[field].isString())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be a string");
    }
    return body[field].asString();
}

std::optional<std::optional<std::string>> patchNullableString(
    const Json::Value &body, const char *field)
{
    // in_place is deliberate: optional's converting assignment/construction is
    // subtle when the contained type is itself an optional, and this spells
    // out "outer engaged (field present), inner = the value or NULL".
    using Patch = std::optional<std::optional<std::string>>;
    if (!body.isMember(field))
    {
        return std::nullopt;
    }
    if (body[field].isNull())
    {
        return Patch(std::in_place, std::nullopt);
    }
    if (!body[field].isString())
    {
        throw std::invalid_argument(std::string("Field '") + field +
                                    "' must be a string or null");
    }
    return Patch(std::in_place, body[field].asString());
}

drogon::HttpResponsePtr jsonResponse(drogon::HttpStatusCode status,
                                     const Json::Value &body)
{
    auto response = drogon::HttpResponse::newHttpJsonResponse(body);
    response->setStatusCode(status);
    response->addHeader("Cache-Control", "no-store");
    response->addHeader("Pragma", "no-cache");
    return response;
}

Json::Value userJson(const UserRecord &user)
{
    Json::Value body;
    body["id"] = Json::Int64(user.id);
    body["employee_id"] = user.employeeId;
    body["email"] = user.email;
    body["display_name"] = user.displayName;
    return body;
}

Json::Value projectJson(const ProjectRecord &project)
{
    Json::Value body;
    body["id"] = Json::Int64(project.id);
    body["name"] = project.name;
    body["description"] = project.description
                              ? Json::Value(*project.description)
                              : Json::Value(Json::nullValue);
    body["created_by_id"] =
        project.createdById ? Json::Value(Json::Int64(*project.createdById))
                            : Json::Value(Json::nullValue);
    body["created_at"] = project.createdAt;
    body["updated_at"] = project.updatedAt;
    return body;
}

Json::Value taskJson(const TaskRecord &task)
{
    Json::Value body;
    body["id"] = Json::Int64(task.id);
    body["parent_task_id"] = task.parentTaskId
                                 ? Json::Value(Json::Int64(*task.parentTaskId))
                                 : Json::Value(Json::nullValue);
    body["project_id"] = Json::Int64(task.projectId);
    body["title"] = task.title;
    body["description"] = task.description ? Json::Value(*task.description)
                                           : Json::Value(Json::nullValue);
    body["status"] = task.status;
    body["type"] = task.type;
    body["discipline"] = task.discipline;
    body["due_at"] =
        task.dueAt ? Json::Value(*task.dueAt) : Json::Value(Json::nullValue);
    body["start_at"] = task.startAt ? Json::Value(*task.startAt)
                                     : Json::Value(Json::nullValue);
    Json::Value assigneeIds(Json::arrayValue);
    for (const auto id : task.assigneeIds)
    {
        assigneeIds.append(Json::Int64(id));
    }
    body["assignee_ids"] = assigneeIds;
    body["created_by_id"] = Json::Int64(task.createdById);
    body["version"] = Json::Int64(task.version);
    body["created_at"] = task.createdAt;
    body["updated_at"] = task.updatedAt;
    return body;
}

Json::Value commentJson(const CommentRecord &comment)
{
    Json::Value body;
    body["id"] = Json::Int64(comment.id);
    body["task_id"] = Json::Int64(comment.taskId);
    body["author_id"] = Json::Int64(comment.authorId);
    body["parent_comment_id"] =
        comment.parentCommentId
            ? Json::Value(Json::Int64(*comment.parentCommentId))
            : Json::Value(Json::nullValue);
    body["body"] = comment.body;
    body["created_at"] = comment.createdAt;
    body["updated_at"] = comment.updatedAt;
    return body;
}

Json::Value noteJson(const TaskNoteRecord &note)
{
    Json::Value body;
    body["id"] = Json::Int64(note.id);
    body["task_id"] = Json::Int64(note.taskId);
    body["author_id"] = Json::Int64(note.authorId);
    body["body"] = note.body;
    body["created_at"] = note.createdAt;
    body["updated_at"] = note.updatedAt;
    return body;
}

Json::Value notificationJson(const NotificationRecord &notification)
{
    Json::Value body;
    body["id"] = Json::Int64(notification.id);
    body["recipient_id"] = Json::Int64(notification.recipientId);
    body["actor_id"] = Json::Int64(notification.actorId);
    body["task_id"] = Json::Int64(notification.taskId);
    body["notification_type"] = notification.notificationType;
    body["message"] = notification.message;
    body["created_at"] = notification.createdAt;
    body["read_at"] = notification.readAt ? Json::Value(*notification.readAt)
                                          : Json::Value(Json::nullValue);
    return body;
}

template <typename Record, typename Mapper>
Json::Value jsonArray(const std::vector<Record> &records, Mapper mapper)
{
    Json::Value array(Json::arrayValue);
    for (const auto &record : records)
    {
        array.append(mapper(record));
    }
    return array;
}
}  // namespace

TaskController::TaskController(TaskService &service,
                               trantor::TaskQueue &workers)
    : service_(service), workers_(workers)
{
}

template <typename Work>
void TaskController::run(const drogon::HttpRequestPtr &request,
                        drogon::AdviceCallback &&callback,
                        Work work)
{
    workers_.runTaskInQueue(
        [request, work = std::move(work), callback = std::move(callback)]()
            mutable {
                try
                {
                    callback(work());
                }
                catch (const std::exception &error)
                {
                    ErrorMiddleware::handleException(
                        error, request, std::move(callback));
                }
            });
}

void TaskController::addTask(const drogon::HttpRequestPtr &request,
                            drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto created =
            service_.addTask(token,
                             requiredString(body, "title"),
                             optionalString(body, "description"),
                             optionalString(body, "status"),
                             optionalString(body, "type"),
                             optionalString(body, "discipline"),
                             optionalString(body, "due_at"),
                             optionalString(body, "start_at"),
                             optionalInt64Array(body, "assignee_ids"),
                             optionalInt64(body, "parent_task_id"),
                             optionalInt64(body, "project_id"));
        Json::Value response;
        response["task"] = taskJson(created);
        return jsonResponse(drogon::k201Created, response);
    });
}

void TaskController::addSubtask(const drogon::HttpRequestPtr &request,
                               drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto created =
            service_.addSubtask(token,
                                requiredInt64(body, "parent_task_id"),
                                requiredString(body, "title"),
                                optionalString(body, "description"),
                                optionalString(body, "status"),
                                optionalString(body, "type"),
                                optionalString(body, "discipline"),
                                optionalString(body, "due_at"),
                                optionalString(body, "start_at"),
                                optionalInt64Array(body, "assignee_ids"),
                                optionalInt64(body, "project_id"));
        Json::Value response;
        response["task"] = taskJson(created);
        return jsonResponse(drogon::k201Created, response);
    });
}

void TaskController::addNote(const drogon::HttpRequestPtr &request,
                            drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto created = service_.addNote(token,
                                              requiredInt64(body, "task_id"),
                                              requiredString(body, "body"));
        Json::Value response;
        response["message"] = "Note created";
        response["note"] = noteJson(created);
        return jsonResponse(drogon::k201Created, response);
    });
}

void TaskController::addComment(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto created =
            service_.addComment(token,
                                requiredInt64(body, "task_id"),
                                requiredString(body, "body"),
                                optionalInt64(body, "parent_comment_id"));
        Json::Value response;
        response["message"] = "Comment created";
        response["comment"] = commentJson(created);
        return jsonResponse(drogon::k201Created, response);
    });
}

void TaskController::addProject(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto created = service_.addProject(
            token, requiredString(body, "name"),
            optionalString(body, "description"));
        Json::Value response;
        response["project"] = projectJson(created);
        return jsonResponse(drogon::k201Created, response);
    });
}

void TaskController::allProjects(const drogon::HttpRequestPtr &request,
                                 drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["projects"] = jsonArray(service_.allProjects(token),
                                         projectJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::changeStatus(const drogon::HttpRequestPtr &request,
                                 drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto updated = service_.changeStatus(
            token, requiredInt64(body, "task_id"), requiredString(body, "status"));
        Json::Value response;
        response["task"] = taskJson(updated);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::updateTask(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        TaskUpdate update;
        update.taskId = requiredInt64(body, "task_id");
        update.title = patchString(body, "title");
        update.description = patchNullableString(body, "description");
        update.status = patchString(body, "status");
        update.type = patchString(body, "type");
        update.discipline = patchString(body, "discipline");
        update.dueAt = patchNullableString(body, "due_at");
        update.startAt = patchNullableString(body, "start_at");
        // A present assignee_ids (null, [] or a list) always means "replace
        // the assignee set"; absent means leave it as-is.
        if (body.isMember("assignee_ids"))
        {
            update.assigneeIds = optionalInt64Array(body, "assignee_ids");
        }
        // project_id is NOT NULL, so there is no "clear it" case.
        if (body.isMember("project_id"))
        {
            update.projectId = requiredInt64(body, "project_id");
        }

        Json::Value response;
        response["task"] =
            taskJson(service_.editTask(token, std::move(update)));
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::deleteTask(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto taskId = requiredInt64(body, "task_id");
        service_.deleteTask(token, taskId);
        Json::Value response;
        response["message"] = "Task deleted";
        response["deleted_task_id"] = Json::Int64(taskId);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::updateNote(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto updated = service_.editNote(token,
                                               requiredInt64(body, "note_id"),
                                               requiredString(body, "body"));
        Json::Value response;
        response["message"] = "Note updated";
        response["note"] = noteJson(updated);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::deleteNote(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto noteId = requiredInt64(body, "note_id");
        service_.deleteNote(token, noteId);
        Json::Value response;
        response["message"] = "Note deleted";
        response["deleted_note_id"] = Json::Int64(noteId);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::updateComment(const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto updated =
            service_.editComment(token,
                                 requiredInt64(body, "comment_id"),
                                 requiredString(body, "body"));
        Json::Value response;
        response["message"] = "Comment updated";
        response["comment"] = commentJson(updated);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::deleteComment(const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto body = requiredBody(request);
    run(request, std::move(callback), [this, token, body]() {
        const auto commentId = requiredInt64(body, "comment_id");
        const auto deletedReplies = service_.deleteComment(token, commentId);
        Json::Value response;
        response["message"] = "Comment deleted";
        response["deleted_comment_id"] = Json::Int64(commentId);
        response["deleted_reply_count"] = Json::Int64(deletedReplies);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::taskDetail(const drogon::HttpRequestPtr &request,
                               drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    const auto taskIdParam = request->getParameter("task_id");
    run(request, std::move(callback), [this, token, taskIdParam]() {
        const std::int64_t taskId = requiredIdParam(taskIdParam, "task_id");
        const auto detail = service_.taskDetail(token, taskId);
        Json::Value response;
        response["task"] = taskJson(detail.task);
        response["subtasks"] = jsonArray(detail.subtasks, taskJson);
        response["notes"] = jsonArray(detail.notes, noteJson);
        response["comments"] = jsonArray(detail.comments, commentJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::allUsers(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["users"] = jsonArray(service_.allUsers(token), userJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::notifications(const drogon::HttpRequestPtr &request,
                                 drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["notifications"] =
            jsonArray(service_.notifications(token), notificationJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::allTasks(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["tasks"] = jsonArray(service_.allTasks(token), taskJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::myTasks(const drogon::HttpRequestPtr &request,
                            drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["tasks"] = jsonArray(service_.myTasks(token), taskJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

void TaskController::completedTasks(const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback)
{
    const auto token = bearerToken(request);
    run(request, std::move(callback), [this, token]() {
        Json::Value response;
        response["tasks"] =
            jsonArray(service_.completedTasks(token), taskJson);
        return jsonResponse(drogon::k200OK, response);
    });
}

}  // namespace taskmanager
