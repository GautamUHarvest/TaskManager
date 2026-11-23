#include "ApiRoutes.h"

#include "../controllers/AuthController.h"
#include "../controllers/CommentController.h"
#include "../controllers/NoteController.h"
#include "../controllers/NotificationController.h"
#include "../controllers/ProjectController.h"
#include "../controllers/TaskController.h"
#include "../controllers/UserController.h"

namespace taskmanager
{

// The whole REST surface, grouped by resource with verb sub-paths. Keep in
// step with apirequirement.md. Writes are POST with the target id in the JSON
// body (the frontend's ApiClient speaks only GET and POST); reads are GET.
void registerApiRoutes(http::Router &router, const ApiControllers &c)
{
    // Auth: /api/auth/*
    router.post("/api/auth/register", c.auth, &AuthController::registerUser);
    router.post("/api/auth/login", c.auth, &AuthController::login);
    router.post("/api/auth/refresh", c.auth, &AuthController::refresh);
    router.post("/api/auth/logout", c.auth, &AuthController::logout);
    router.get("/api/auth/me", c.auth, &AuthController::profile);

    // Tasks: /api/task/*
    router.post("/api/task/add", c.tasks, &TaskController::addTask);
    router.post("/api/task/subtask", c.tasks, &TaskController::addSubtask);
    router.post("/api/task/status", c.tasks, &TaskController::changeStatus);
    router.post("/api/task/update", c.tasks, &TaskController::updateTask);
    router.post("/api/task/delete", c.tasks, &TaskController::deleteTask);
    // Flags the task blocked and alerts the member held responsible, live
    // over the WebSocket when they are connected.
    router.post("/api/task/block", c.tasks, &TaskController::raiseBlocker);
    router.get("/api/task/detail", c.tasks, &TaskController::taskDetail);
    router.get("/api/task/all", c.tasks, &TaskController::allTasks);
    router.get("/api/task/mine", c.tasks, &TaskController::myTasks);
    router.get("/api/task/completed", c.tasks, &TaskController::completedTasks);
    router.get("/api/task/project", c.tasks, &TaskController::projectTasks);

    // Task notes and comments: /api/task/note*, /api/task/comment*
    router.post("/api/task/note", c.notes, &NoteController::addNote);
    router.post("/api/task/note/update", c.notes, &NoteController::updateNote);
    router.post("/api/task/note/delete", c.notes, &NoteController::deleteNote);
    router.post("/api/task/comment", c.comments, &CommentController::addComment);
    router.post("/api/task/comment/update",
                c.comments,
                &CommentController::updateComment);
    router.post("/api/task/comment/delete",
                c.comments,
                &CommentController::deleteComment);

    // Projects: /api/project/*
    router.post("/api/project/add", c.projects, &ProjectController::addProject);
    router.get("/api/project/all", c.projects, &ProjectController::allProjects);

    // Users: /api/user/*
    router.get("/api/user/all", c.users, &UserController::allUsers);

    // Notifications: /api/notification/*
    router.get("/api/notification/all",
               c.notifications,
               &NotificationController::notifications);
    router.get("/api/notification/pending-blockers",
               c.notifications,
               &NotificationController::pendingBlockers);
    router.post("/api/notification/ack",
                c.notifications,
                &NotificationController::acknowledge);

    router.installCorsPreflight();
}

}  // namespace taskmanager
