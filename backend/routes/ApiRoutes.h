#pragma once

#include "../http/Router.h"

#include <memory>

namespace taskmanager
{

class AuthController;
class TaskController;
class ProjectController;
class NoteController;
class CommentController;
class NotificationController;
class UserController;

struct ApiControllers
{
    std::shared_ptr<AuthController> auth;
    std::shared_ptr<TaskController> tasks;
    std::shared_ptr<ProjectController> projects;
    std::shared_ptr<NoteController> notes;
    std::shared_ptr<CommentController> comments;
    std::shared_ptr<NotificationController> notifications;
    std::shared_ptr<UserController> users;
};

// Registers every REST endpoint and the shared CORS preflight. The WebSocket
// route (/ws/notifications) registers itself — see BlockerSocketController.
void registerApiRoutes(http::Router &router, const ApiControllers &controllers);

}  // namespace taskmanager
