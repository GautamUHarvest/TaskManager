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
# Allowed browser origins (comma-separated). Default: the Flutter dev server
# plus http://<each IPv4 of this host>, so the nginx-served app opened at the
# machine's LAN IP (e.g. http://192.168.0.23) passes the WebSocket Origin
# check. Same-origin REST through nginx never needs this, but /ws/ does — a
# missing entry upgrades the socket and closes it instantly.
if [ -z "${TASK_MANAGER_CORS_ORIGIN:-}" ]; then
    TASK_MANAGER_CORS_ORIGIN="http://localhost:5000"
    for ip in $(hostname -I 2>/dev/null || true); do
        case "$ip" in
            *:*) ;;  # skip IPv6
            *) TASK_MANAGER_CORS_ORIGIN="$TASK_MANAGER_CORS_ORIGIN,http://$ip" ;;
        esac
    done
fi
export TASK_MANAGER_CORS_ORIGIN
echo "Allowed origins (CORS + WebSocket): $TASK_MANAGER_CORS_ORIGIN"
# Auth uses the localStorage refresh-token model (token in the JSON body, no
# cookies), so there are no refresh-cookie env vars to set here.

exec "$backend_dir/build/TaskManagerBackend" "$@"
