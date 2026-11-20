#include <drogon/drogon.h>
#include <trantor/utils/ConcurrentTaskQueue.h>

#include "config/AppConfig.h"
#include "controllers/AuthController.h"
#include "controllers/CommentController.h"
#include "controllers/NoteController.h"
#include "controllers/NotificationController.h"
#include "controllers/ProjectController.h"
#include "controllers/TaskController.h"
#include "controllers/UserController.h"
#include "db/Migrations.h"
#include "db/Sqlite.h"
#include "error_middleware/ErrorMiddleware.h"
#include "http/Dispatcher.h"
#include "http/Router.h"
#include "repositories/AuthRepository.h"
#include "repositories/CommentRepository.h"
#include "repositories/NoteRepository.h"
#include "repositories/NotificationRepository.h"
#include "repositories/ProjectRepository.h"
#include "repositories/TaskRepository.h"
#include "repositories/UserRepository.h"
#include "routes/ApiRoutes.h"
#include "services/AuthService.h"
#include "services/BlockerHub.h"
#include "services/CommentService.h"
#include "services/NoteService.h"
#include "services/NotificationService.h"
#include "services/ProjectService.h"
#include "services/TaskService.h"
#include "services/UserService.h"

#include <memory>
#include <sys/stat.h>

// Composition root: builds every layer by hand (no Drogon codegen, no DI
// container) — config -> database -> repositories -> services -> controllers
// -> routes. Everything here lives for the whole process.
int main()
{
    using namespace taskmanager;
    try
    {
        umask(S_IRWXG | S_IRWXO);
        const auto config = AppConfig::fromEnvironment();

        db::initializeDatabase(config.databasePath, config.migrationsDir);
        const db::Database database(config.databasePath);

        AuthRepository authRepository(database);
        UserRepository userRepository(database);
        ProjectRepository projectRepository(database);
        TaskRepository taskRepository(database);
        NoteRepository noteRepository(database);
        CommentRepository commentRepository(database);
        NotificationRepository notificationRepository(database);

        AuthService authService(authRepository, config.jwtSecret);
        UserService userService(userRepository);
        ProjectService projectService(projectRepository);
        TaskService taskService(taskRepository,
                                projectRepository,
                                userRepository,
                                noteRepository,
                                commentRepository);
        NoteService noteService(noteRepository);
        CommentService commentService(
            commentRepository, taskRepository, notificationRepository);
        NotificationService notificationService(notificationRepository);

        // All blocking work (scrypt, SQLite) runs here, never on the event
        // loop. The name predates the task endpoints; it serves all of them.
        trantor::ConcurrentTaskQueue workers(2, "auth-workers");
        const http::Dispatcher dispatcher(authService, workers);

        // The WebSocket controller is constructed by Drogon itself, so its
        // dependencies are handed over through the hub instead. Token checks
        // read SQLite, so they go to the same worker queue.
        BlockerHub::instance().configure(&authService, &workers);

        auto &app = drogon::app();
        app.registerMiddleware(std::make_shared<ErrorMiddleware>());

        http::Router router(app);
        registerApiRoutes(
            router,
            ApiControllers{
                std::make_shared<AuthController>(authService, dispatcher),
                std::make_shared<TaskController>(taskService, dispatcher),
                std::make_shared<ProjectController>(projectService, dispatcher),
                std::make_shared<NoteController>(noteService, dispatcher),
                std::make_shared<CommentController>(commentService, dispatcher),
                std::make_shared<NotificationController>(notificationService,
                                                         dispatcher),
                std::make_shared<UserController>(userService, dispatcher)});

        // Exceptions thrown outside the middleware chain, and unknown routes,
        // get the same error shape as everything else.
        app.setExceptionHandler([](const std::exception &error,
                                   const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback) {
            ErrorMiddleware::handleException(error, request, std::move(callback));
        });
        app.setDefaultHandler(
            [](const drogon::HttpRequestPtr &, drogon::AdviceCallback &&callback) {
                callback(ErrorMiddleware::notFoundResponse());
            });

        app.addListener(config.listenAddress,
                        config.port,
                        true,
                        config.tlsCertificate,
                        config.tlsPrivateKey)
            .run();
        workers.stop();
    }
    catch (const std::exception &error)
    {
        LOG_FATAL << "Task Manager startup failed: " << error.what();
        return 1;
    }
    return 0;
}
