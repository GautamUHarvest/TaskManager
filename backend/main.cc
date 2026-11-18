#include <drogon/drogon.h>
#include <trantor/utils/ConcurrentTaskQueue.h>

#include "controllers/AuthController.h"
#include "controllers/TaskController.h"
#include "error_middleware/ErrorMiddleware.h"
#include "repositories/AuthRepository.h"
#include "repositories/TaskRepository.h"
#include "routes/AuthRoutes.h"
#include "routes/TaskRoutes.h"
#include "services/AuthService.h"
#include "services/TaskService.h"

#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <string>
#include <sys/stat.h>

namespace
{
std::string requiredEnvironment(const char *name)
{
    const char *value = std::getenv(name);
    if (!value || value[0] == '\0')
    {
        throw std::runtime_error(std::string(name) + " must be configured");
    }
    return value;
}

std::string environmentOr(const char *name, const std::string &fallback)
{
    const char *value = std::getenv(name);
    return value && value[0] != '\0' ? value : fallback;
}

}  // namespace

int main()
{
    try
    {
        umask(S_IRWXG | S_IRWXO);
        const auto address = environmentOr(
            "TASK_MANAGER_LISTEN_ADDRESS", "0.0.0.0");

        const auto databasePath = environmentOr(
            "TASK_MANAGER_DATABASE_PATH", "task_manager.sqlite3");
            
        const auto migrationsPath = environmentOr(
            "TASK_MANAGER_MIGRATIONS_DIR", TASK_MANAGER_MIGRATIONS_DIR);

        taskmanager::AuthRepository repository(
            databasePath, migrationsPath);
        repository.initialize();

        taskmanager::AuthService auth(
            repository, requiredEnvironment("TASK_MANAGER_JWT_SECRET"));
        trantor::ConcurrentTaskQueue authWorkers(2, "auth-workers");
        drogon::app().registerMiddleware(
            std::make_shared<taskmanager::ErrorMiddleware>());
        auto authController =
            std::make_shared<taskmanager::AuthController>(auth, authWorkers);
        taskmanager::registerAuthRoutes(authController);

        taskmanager::TaskRepository taskRepository(databasePath);
        taskmanager::TaskService taskService(auth, taskRepository);
        auto taskController =
            std::make_shared<taskmanager::TaskController>(taskService,
                                                          authWorkers);
        taskmanager::registerTaskRoutes(taskController);
        drogon::app().setExceptionHandler(
            [](const std::exception &error,
               const drogon::HttpRequestPtr &request,
               drogon::AdviceCallback &&callback) {
                taskmanager::ErrorMiddleware::handleException(
                    error, request, std::move(callback));
            });
        drogon::app().setDefaultHandler(
            [](const drogon::HttpRequestPtr &,
               drogon::AdviceCallback &&callback) {
                callback(taskmanager::ErrorMiddleware::notFoundResponse());
            });

        const auto certificate = requiredEnvironment("TASK_MANAGER_TLS_CERT");
        const auto privateKey = requiredEnvironment("TASK_MANAGER_TLS_KEY");
        const auto portText = environmentOr("TASK_MANAGER_PORT", "5555");
        std::size_t parsed = 0;
        const auto port = std::stoul(portText, &parsed);
        if (parsed != portText.size() || port == 0 || port > 65535)
        {
            throw std::runtime_error("TASK_MANAGER_PORT must be 1 to 65535");
        }

        drogon::app()
            .addListener(address,
                         static_cast<uint16_t>(port),
                         true,
                         certificate,
                         privateKey)
            .run();
        authWorkers.stop();
    }
    catch (const std::exception &error)
    {
        LOG_FATAL << "Task Manager startup failed: " << error.what();
        return 1;
    }
    return 0;
}
