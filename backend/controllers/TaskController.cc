#include "TaskController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"
#include "../services/BlockerHub.h"

#include <utility>

namespace taskmanager
{
using namespace http;

namespace
{
// The create-style task fields shared by /task/add and /task/subtask.
TaskInput taskInput(const Json::Value &body)
{
    TaskInput input;
    input.title = requiredString(body, "title");
    input.description = optionalString(body, "description");
    input.status = optionalString(body, "status");
    input.type = optionalString(body, "type");
    input.discipline = optionalString(body, "discipline");
    input.dueAt = optionalString(body, "due_at");
    input.startAt = optionalString(body, "start_at");
    input.assigneeIds = optionalInt64Array(body, "assignee_ids");
    input.parentTaskId = optionalInt64(body, "parent_task_id");
    input.projectId = optionalInt64(body, "project_id");
    return input;
}

Json::Value taskEnvelope(const TaskRecord &task)
{
    Json::Value response;
    response["task"] = toJson(task);
    return response;
}

Json::Value tasksEnvelope(const std::vector<TaskRecord> &tasks)
{
    Json::Value response;
    response["tasks"] = toJsonArray(tasks);
    return response;
}
}  // namespace

TaskController::TaskController(TaskService &service,
                               const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void TaskController::addTask(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto created =
                service_.addTask(actor, taskInput(requiredBody(request)));
            return jsonResponse(drogon::k201Created, taskEnvelope(created));
        });
}

void TaskController::addSubtask(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto parentTaskId = requiredInt64(body, "parent_task_id");
            const auto created =
                service_.addSubtask(actor, parentTaskId, taskInput(body));
            return jsonResponse(drogon::k201Created, taskEnvelope(created));
        });
}

void TaskController::changeStatus(const drogon::HttpRequestPtr &request,
                                  drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto updated =
                service_.changeStatus(actor,
                                      requiredInt64(body, "task_id"),
                                      requiredString(body, "status"));
            return jsonResponse(drogon::k200OK, taskEnvelope(updated));
        });
}

void TaskController::updateTask(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            TaskUpdate update;
            update.taskId = requiredInt64(body, "task_id");
            update.title = patchString(body, "title");
            update.description = patchNullableString(body, "description");
            update.status = patchString(body, "status");
            update.type = patchString(body, "type");
            update.discipline = patchString(body, "discipline");
            update.dueAt = patchNullableString(body, "due_at");
            update.startAt = patchNullableString(body, "start_at");
            // A present assignee_ids (null, [] or a list) always means
            // "replace the assignee set"; absent means leave it as-is.
            if (body.isMember("assignee_ids"))
            {
                update.assigneeIds = optionalInt64Array(body, "assignee_ids");
            }
            // project_id is NOT NULL, so there is no "clear it" case.
            if (body.isMember("project_id"))
            {
                update.projectId = requiredInt64(body, "project_id");
            }
            const auto updated = service_.editTask(actor, std::move(update));
            return jsonResponse(drogon::k200OK, taskEnvelope(updated));
        });
}

void TaskController::deleteTask(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto taskId = requiredInt64(requiredBody(request), "task_id");
            service_.deleteTask(actor, taskId);
            Json::Value response;
            response["message"] = "Task deleted";
            response["deleted_task_id"] = Json::Int64(taskId);
            return jsonResponse(drogon::k200OK, response);
        });
}

void TaskController::raiseBlocker(const drogon::HttpRequestPtr &request,
                                  drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto raised = service_.raiseBlocker(
                actor,
                requiredInt64(body, "task_id"),
                requiredInt64(body, "responsible_user_id"),
                requiredString(body, "message"));

            // Push to the responsible member's live sockets, if any. Someone
            // offline gets nothing here — the stored notification is shown on
            // their next connect, via /notification/pending-blockers.
            Json::Value event;
            event["type"] = "blocker";
            event["notification"] = toJson(raised.notification);
            event["task"] = toJson(raised.task);
            BlockerHub::instance().pushTo(raised.notification.recipientId,
                                          event);

            Json::Value response;
            response["message"] = "Blocker raised";
            response["task"] = toJson(raised.task);
            response["notification"] = toJson(raised.notification);
            return jsonResponse(drogon::k201Created, response);
        });
}

void TaskController::taskDetail(const drogon::HttpRequestPtr &request,
                                drogon::AdviceCallback &&callback)
{
    const auto taskIdParam = request->getParameter("task_id");
    dispatcher_.authenticated(
        request, std::move(callback), [this, taskIdParam](const UserRecord &) {
            const auto detail =
                service_.taskDetail(requiredIdParam(taskIdParam, "task_id"));
            Json::Value response;
            response["task"] = toJson(detail.task);
            response["subtasks"] = toJsonArray(detail.subtasks);
            response["notes"] = toJsonArray(detail.notes);
            response["comments"] = toJsonArray(detail.comments);
            return jsonResponse(drogon::k200OK, response);
        });
}

void TaskController::allTasks(const drogon::HttpRequestPtr &request,
                              drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &) {
            return jsonResponse(drogon::k200OK,
                                tasksEnvelope(service_.allTasks()));
        });
}

void TaskController::myTasks(const drogon::HttpRequestPtr &request,
                             drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &actor) {
            return jsonResponse(drogon::k200OK,
                                tasksEnvelope(service_.myTasks(actor)));
        });
}

void TaskController::completedTasks(const drogon::HttpRequestPtr &request,
                                    drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this](const UserRecord &) {
            return jsonResponse(drogon::k200OK,
                                tasksEnvelope(service_.completedTasks()));
        });
}

void TaskController::projectTasks(const drogon::HttpRequestPtr &request,
                                  drogon::AdviceCallback &&callback)
{
    const auto projectIdParam = request->getParameter("project_id");
    dispatcher_.authenticated(
        request,
        std::move(callback),
        [this, projectIdParam](const UserRecord &) {
            return jsonResponse(
                drogon::k200OK,
                tasksEnvelope(service_.projectTasks(
                    requiredIdParam(projectIdParam, "project_id"))));
        });
}

}  // namespace taskmanager
