#include "AppConfig.h"

#include <cstdlib>
#include <stdexcept>

#ifndef TASK_MANAGER_MIGRATIONS_DIR
#define TASK_MANAGER_MIGRATIONS_DIR "migrations"
#endif

namespace taskmanager
{
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

std::uint16_t parsePort(const std::string &text)
{
    std::size_t parsed = 0;
    unsigned long port = 0;
    try
    {
        port = std::stoul(text, &parsed);
    }
    catch (const std::exception &)
    {
        parsed = 0;
    }
    if (parsed == 0 || parsed != text.size() || port == 0 || port > 65535)
    {
        throw std::runtime_error("TASK_MANAGER_PORT must be 1 to 65535");
    }
    return static_cast<std::uint16_t>(port);
}
}  // namespace

AppConfig AppConfig::fromEnvironment()
{
    AppConfig config;
    config.listenAddress =
        environmentOr("TASK_MANAGER_LISTEN_ADDRESS", "0.0.0.0");
    config.port = parsePort(environmentOr("TASK_MANAGER_PORT", "5555"));
    config.databasePath =
        environmentOr("TASK_MANAGER_DATABASE_PATH", "task_manager.sqlite3");
    config.migrationsDir = environmentOr("TASK_MANAGER_MIGRATIONS_DIR",
                                         TASK_MANAGER_MIGRATIONS_DIR);
    config.jwtSecret = requiredEnvironment("TASK_MANAGER_JWT_SECRET");
    config.tlsCertificate = requiredEnvironment("TASK_MANAGER_TLS_CERT");
    config.tlsPrivateKey = requiredEnvironment("TASK_MANAGER_TLS_KEY");
    return config;
}

}  // namespace taskmanager
