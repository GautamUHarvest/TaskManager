# Task Manager authentication API

The backend uses Drogon for HTTP, raw SQLite for storage, and OpenSSL for
password and token utilities. Code is layered, one module per resource
(auth, task, project, note, comment, notification, user):

| Directory | Holds |
| --- | --- |
| `routes/ApiRoutes.cc` | The whole REST route table (path, method, handler) |
| `controllers/` | One controller per resource: parse the request, call a service, map the result to JSON |
| `services/` | Business rules and permissions; `TaskRules` holds the pure validation rules |
| `repositories/` | SQL, one repository per table group; `Rows` holds shared column lists and row mappers |
| `models/` | Plain record structs |
| `http/` | Shared HTTP plumbing: `Router` (route + CORS preflight registry), `Dispatcher` (worker-queue + auth), request parsing, JSON mappers, response builders |
| `db/` | `Sqlite` (Connection, Statement, Transaction, typed `SqliteError`) and `Migrations` |
| `common/` | `Errors.h` (every exception type and its HTTP status) and text helpers |
| `security/` | Password hashing, JWTs, input validation, origin allowlist, rate limiter |
| `config/` | `AppConfig`: all environment variables, read once at startup |
| `error_middleware/` | Maps exceptions to `{"error": ...}` responses and adds CORS headers |

Request flow is: `Router` -> `ErrorMiddleware` -> controller -> `Dispatcher`
(worker queue; verifies the bearer token) -> service -> repository -> SQLite.
Services receive the signed-in user, never a raw token. Drogon catches
exceptions thrown outside the middleware chain, so `main.cc` also forwards its
exception hook to the same error middleware. Unmatched routes use the
middleware's JSON 404 response.

Adding an endpoint: a repository method if new SQL is needed, a service
method, a controller handler, and one line in `routes/ApiRoutes.cc` — which
also makes CORS preflight accept it.

## Configuration

Set these environment variables before starting the backend:

| Variable | Required | Purpose |
| --- | --- | --- |
| `TASK_MANAGER_JWT_SECRET` | yes | HMAC key; use at least 32 cryptographically random bytes |
| `TASK_MANAGER_DATABASE_PATH` | no | SQLite file path; defaults to `task_manager.sqlite3` |
| `TASK_MANAGER_MIGRATIONS_DIR` | no | SQL migration directory; defaults to the build's copied migrations |
| `TASK_MANAGER_TLS_CERT` | yes | PEM certificate for the HTTPS listener |
| `TASK_MANAGER_TLS_KEY` | yes | Matching private key; protect its file permissions |
| `TASK_MANAGER_CORS_ORIGIN` | no | Comma-separated list of exact browser origins allowed for CORS and the `/ws/notifications` socket, e.g. `http://localhost:5000,http://192.168.0.23`; no paths |
| `TASK_MANAGER_LISTEN_ADDRESS` | no | Listener address; defaults to `0.0.0.0` |
| `TASK_MANAGER_PORT` | no | HTTPS port; defaults to `5555` |

Use a secret manager or protected service environment for secrets. Do not put
secrets in source files or commit them. The API listener is HTTPS-only and
startup fails if its certificate or key is missing. The process uses a
restrictive umask and restricts an existing SQLite database file to its owner.

For Flutter Web, set `TASK_MANAGER_CORS_ORIGIN` to the exact origin shown by
the Flutter development server. The API allows only that origin and handles
preflight requests for every registered route; it does not enable
credentialed cross-origin requests.

The database applies numbered SQL files in `migrations/` once, in version
order. It enables SQLite foreign keys on every connection and WAL mode for the
database. Back up the database together with its WAL state using a SQLite-aware
backup method.

## Startup

`main.cc` initializes SQLite and applies pending migrations, loads the JWT
configuration, creates the auth worker queue,
registers the controller and global exception handler, configures the HTTPS
listener, and starts Drogon's event loop. Startup stops with a clear error if
required secrets or TLS files are missing.

Install the Drogon, libcurl, OpenSSL, and SQLite development packages first.
Build and run from the backend directory after setting the required
environment variables above:

```sh 
cmake -S . -B build
cmake --build build -j2
./build/TaskManagerBackend
```

For local development, run the launcher from the backend directory. It
generates a JWT secret if needed (and reuses it on later runs), rebuilds the
backend, and binds the API to localhost.

```sh
./run-local.sh
```

For a local Postman demo, use `https://localhost:5555` and disable SSL
certificate verification only for the local self-signed certificate. The
launcher uses `dev-cert.pem` and `dev-key.pem`; the certificate and key are for
local testing only.

The process currently runs in the foreground. On the Raspberry Pi, it should
be launched by a service manager such as systemd for automatic start and
restart; a systemd unit has not been added yet.

## Routes

All routes use JSON except authenticated requests, which use the
`Authorization: Bearer <access-token>` header.

| Method and path | Request fields | Result |
| --- | --- | --- |
| `POST /api/auth/register` | `employee_id`, `email`, `display_name`, `password` | Creates an active account immediately; sign in with its employee ID or email and password |
| `POST /api/auth/login` | `login` (employee ID or email), `password` | Returns access and refresh tokens in the JSON body |
| `POST /api/auth/refresh` | `refresh_token` | Rotates the refresh token and issues a new access token |
| `POST /api/auth/logout` | Bearer access token | Revokes its refresh session; any issued access token expires within 10 minutes |
| `GET /api/auth/me` | Bearer access token | Returns the authenticated user's profile |

Task-domain routes are all Bearer-protected. The full request/response contract
lives in [apirequirement.md](../apirequirement.md); the edit/delete group is
summarised here because it is the only part with a per-record permission rule:

| Method and path | Request fields | Who may call it |
| --- | --- | --- |
| `POST /api/task/update` | `task_id` plus any editable field (partial; an explicit `null` clears a nullable column) | The task's creator or any of its assignees |
| `POST /api/task/delete` | `task_id` | The task's creator only; refused with `400` while the task still has subtasks |
| `POST /api/task/note/update` | `note_id`, `body` | The note's author only |
| `POST /api/task/note/delete` | `note_id` | The note's author only |
| `POST /api/task/comment/update` | `comment_id`, `body` | The comment's author only |
| `POST /api/task/comment/delete` | `comment_id` | The comment's author only; nested replies cascade |

### Blockers and the WebSocket

`POST /api/task/block` flags a task as blocked on another member — setting the
status to `blocked`, logging a `blocked` event and storing a `blocker`
notification — then pushes that notification to the member's open sockets.

The socket lives at `/ws/notifications` and is the one place this backend uses
a Drogon auto-registering controller (`controllers/BlockerSocketController`),
because Drogon offers no non-macro WebSocket route registration. It
authenticates by **first message**, not by header or query string:

```
client -> {"type":"auth","access_token":"<jwt>"}
server -> {"type":"auth_ok","user_id":3}
```

A browser cannot set `Authorization` on a WebSocket handshake, and a token in
the query string would be logged by nginx and Drogon — which this README
forbids below. Unauthenticated sockets are closed after 10 seconds, and the
handshake's `Origin` is checked against `TASK_MANAGER_CORS_ORIGIN` because CORS
does not apply to WebSockets. **Behind nginx this check still applies even
though the REST API is same-origin:** the list must include the origin users
open the app from (e.g. `http://192.168.0.23`), or the socket upgrades and is
immediately closed — and phones fall back to seeing blockers only on reload.
Token verification reads SQLite, so it is
dispatched to the `auth-workers` queue rather than run on the event loop.

Live delivery is best-effort: `services/BlockerHub` keeps an in-memory map of
user id → connections, so it is **per process**, the same single-process
assumption the SQLite setup and the IP rate limiter already make. A member with
no open tab is covered by the stored notification, which the client replays via
`GET /api/notification/pending-blockers` and dismisses with
`POST /api/notification/ack`.

**nginx must be told to proxy WebSockets** — without this the handshake fails
and clients reconnect forever:

```nginx
location /ws/ {
    proxy_pass https://127.0.0.1:5555;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

A caller with a valid token who fails one of these rules gets `403 Forbidden`
(`ForbiddenError` in `common/Errors.h`, mapped in `ErrorMiddleware`).
Deleting a task also clears its notes, events and notifications by hand,
because those tables reference `tasks` with `ON DELETE RESTRICT` (migration
001); assignees and comments cascade on their own (migration 006).

Passwords currently enforce the requested six-character minimum, uppercase,
number, and special-character requirements. A longer minimum (at least 12
characters) is recommended before production deployment. Passwords are stored
as scrypt hashes. Access JWTs use HS256 and expire after 10 minutes. Refresh
tokens are random, rotated on use, and only their SHA-256 hashes are stored in
SQLite. Registration is limited to 25 active accounts. IP-based request limits
are held in process memory, so they reset on restart and are not shared across
multiple backend instances; run one backend process with this SQLite database.

Registration no longer requires email verification. Existing accounts awaiting
verification are activated by migration `003_disable_email_verification.sql`.

Refresh tokens are returned in the JSON body of `POST /api/auth/login` and
`POST /api/auth/refresh`, and the client sends one back in the
`POST /api/auth/refresh` body. The token rotates on every refresh, so the
client must replace the one it holds with the new one. No cookies are used.
The Flutter Web client persists its refresh token in `localStorage` so a
reload can resurrect the session — a deliberate tradeoff that keeps the app
working over plain HTTP on a LAN box, at the cost of exposing the token to
XSS. Keep access tokens in memory only and never put bearer tokens in URLs or
application logs.

CORS uses an exact-origin allowlist, not a wildcard: set
`TASK_MANAGER_CORS_ORIGIN` to the frontend origin, or a comma-separated list
of them when the app is opened from more than one (dev server and LAN IP).
