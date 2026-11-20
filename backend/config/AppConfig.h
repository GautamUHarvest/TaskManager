#pragma once

#include <cstdint>
#include <string>

namespace taskmanager
{

// Runtime configuration. Environment variables are the only source — the
// Drogon config.json/config.yaml in this directory are not loaded. See the
// variable table in backend/README.md.
struct AppConfig
{
    std::string listenAddress;   // TASK_MANAGER_LISTEN_ADDRESS, default 0.0.0.0
    std::uint16_t port;          // TASK_MANAGER_PORT, default 5555
    std::string databasePath;    // TASK_MANAGER_DATABASE_PATH
    std::string migrationsDir;   // TASK_MANAGER_MIGRATIONS_DIR
    std::string jwtSecret;       // TASK_MANAGER_JWT_SECRET (required)
    std::string tlsCertificate;  // TASK_MANAGER_TLS_CERT (required)
    std::string tlsPrivateKey;   // TASK_MANAGER_TLS_KEY (required)

    // Reads and validates everything up front, so a misconfigured server
    // fails at startup rather than on first use. Throws std::runtime_error
    // naming the offending variable.
    static AppConfig fromEnvironment();
};

}  // namespace taskmanager
