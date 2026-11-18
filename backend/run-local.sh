#!/bin/sh
set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

cmake --build "$backend_dir/build" --parallel 2

export TASK_MANAGER_LISTEN_ADDRESS="${TASK_MANAGER_LISTEN_ADDRESS:-0.0.0.0}"
if [ -z "${TASK_MANAGER_JWT_SECRET:-}" ]; then
    dev_secret_file="$backend_dir/.dev-jwt-secret"
    if [ ! -s "$dev_secret_file" ]; then
        (umask 077; openssl rand -base64 48 > "$dev_secret_file")
    fi
    TASK_MANAGER_JWT_SECRET=$(cat "$dev_secret_file")
fi
export TASK_MANAGER_JWT_SECRET
export TASK_MANAGER_TLS_CERT="${TASK_MANAGER_TLS_CERT:-$backend_dir/dev-cert.pem}"
export TASK_MANAGER_TLS_KEY="${TASK_MANAGER_TLS_KEY:-$backend_dir/dev-key.pem}"
export TASK_MANAGER_DATABASE_PATH="${TASK_MANAGER_DATABASE_PATH:-$backend_dir/task_manager.sqlite3}"
export TASK_MANAGER_CORS_ORIGIN="${TASK_MANAGER_CORS_ORIGIN:-http://localhost:5000}"

exec "$backend_dir/build/TaskManagerBackend" "$@"
