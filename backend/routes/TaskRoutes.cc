#include "TaskRoutes.h"

#include "../controllers/TaskController.h"

#include <drogon/HttpAppFramework.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>

namespace taskmanager
{
namespace
{
// CORS preflight for the task/user/notification routes. Mirrors the auth
// routes' preflight (AuthRoutes.cc); sharing one implementation is part of the
// planned modularity pass. Only needed for direct cross-origin dev — nginx
// same-origin deployment never sends these OPTIONS requests.
bool isTaskRoute(const std::string &path)
{
    constexpr std::array<std::string_view, 19> paths = {
        "/api/task/add",
        "/api/task/subtask",
        "/api/task/note",
        "/api/task/note/update",
        "/api/task/note/delete",
        "/api/task/comment",
        "/api/task/comment/update",
        "/api/task/comment/delete",
        "/api/task/status",
        "/api/task/update",
        "/api/task/delete",
        "/api/task/detail",
        "/api/task/all",
        "/api/task/mine",
        "/api/task/completed",
        "/api/project/add",
        "/api/project/all",
        "/api/user/all",
        "/api/notification/all"};
    return std::find(paths.begin(), paths.end(), path) != paths.end();
}

std::string expectedMethod(const std::string &path)
{
    constexpr std::array<std::string_view, 12> postPaths = {
        "/api/task/add",
        "/api/task/subtask",
        "/api/task/note",
        "/api/task/note/update",
        "/api/task/note/delete",
        "/api/task/comment",
        "/api/task/comment/update",
        "/api/task/comment/delete",
        "/api/task/status",
        "/api/task/update",
        "/api/task/delete",
        "/api/project/add"};
    return std::find(postPaths.begin(), postPaths.end(), path) != postPaths.end()
               ? "POST"
               : "GET";
}

bool hasOnlyAllowedHeaders(const std::string &headers)
{
    std::istringstream stream(headers);
    std::string header;
    while (std::getline(stream, header, ','))
    {
        const auto first = header.find_first_not_of(" \t");
        const auto last = header.find_last_not_of(" \t");
        if (first == std::string::npos)
        {
            continue;
        }
        header = header.substr(first, last - first + 1);
        std::transform(header.begin(),
                       header.end(),
                       header.begin(),
                       [](unsigned char character) {
                           return static_cast<char>(std::tolower(character));
                       });
        if (header != "authorization" && header != "content-type")
        {
            return false;
        }
    }
    return true;
}

drogon::HttpResponsePtr corsPreflightResponse(
    const drogon::HttpRequestPtr &request)
{
    auto response = drogon::HttpResponse::newHttpResponse();
    response->addHeader("Vary", "Origin");

    const auto *configuredOrigin = std::getenv("TASK_MANAGER_CORS_ORIGIN");
    const auto &origin = request->getHeader("origin");
    if (!configuredOrigin || configuredOrigin[0] == '\0' ||
        origin != configuredOrigin)
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    const auto &requestedMethod =
        request->getHeader("access-control-request-method");
    if (requestedMethod != expectedMethod(request->path()))
    {
        response->setStatusCode(drogon::k405MethodNotAllowed);
        return response;
    }
    if (!hasOnlyAllowedHeaders(
            request->getHeader("access-control-request-headers")))
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    response->setStatusCode(drogon::k204NoContent);
    response->addHeader("Access-Control-Allow-Origin", origin);
    response->addHeader("Access-Control-Allow-Credentials", "true");
    response->addHeader("Access-Control-Allow-Methods", requestedMethod);
    response->addHeader("Access-Control-Allow-Headers",
                        "Authorization, Content-Type");
    response->addHeader("Access-Control-Max-Age", "600");
    return response;
}
}  // namespace

// Endpoints are grouped by resource with verb sub-paths, mirroring the auth
// routes (/api/auth/<verb>): tasks under /api/task/, users under /api/user/,
// notifications under /api/notification/. All GET + ErrorMiddleware except the
// create, which is POST. A CORS preflight advice (below) handles OPTIONS for
// these routes so the frontend works cross-origin (direct dev); same-origin
// nginx deployment does not send preflight.
void registerTaskRoutes(const std::shared_ptr<TaskController> &controller)
{
    auto &app = drogon::app();

    // CORS preflight for all task/user/notification routes. Runs after the auth
    // routes' preflight advice, which now passes through non-auth OPTIONS.
    app.registerSyncAdvice([](const drogon::HttpRequestPtr &request) {
        if (request->method() != drogon::Options || !isTaskRoute(request->path()))
        {
            return drogon::HttpResponsePtr{};
        }
        return corsPreflightResponse(request);
    });

    // Tasks: /api/task/*
    app.registerHandler(
        "/api/task/add",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->addTask(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/subtask",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->addSubtask(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/note",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->addNote(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/comment",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->addComment(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/status",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->changeStatus(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    // Edit / delete. All POST (the frontend's ApiClient only speaks GET and
    // POST), with the target id in the JSON body.
    app.registerHandler(
        "/api/task/update",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->updateTask(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/delete",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->deleteTask(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/note/update",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->updateNote(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/note/delete",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->deleteNote(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/comment/update",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->updateComment(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/comment/delete",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->deleteComment(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/detail",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->taskDetail(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/all",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->allTasks(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/mine",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->myTasks(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/task/completed",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->completedTasks(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    // Projects: /api/project/*
    app.registerHandler(
        "/api/project/add",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->addProject(request, std::move(callback));
        },
        {drogon::Post, "taskmanager::ErrorMiddleware"});

    app.registerHandler(
        "/api/project/all",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->allProjects(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    // Users: /api/user/*
    app.registerHandler(
        "/api/user/all",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->allUsers(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});

    // Notifications: /api/notification/*
    app.registerHandler(
        "/api/notification/all",
        [controller](const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback) {
            controller->notifications(request, std::move(callback));
        },
        {drogon::Get, "taskmanager::ErrorMiddleware"});
}

}  // namespace taskmanager
