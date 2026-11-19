# Task Manager authentication API

The backend uses Drogon routes and controllers, a SQLite repository, and
OpenSSL password and token utilities. URL and
HTTP-method mappings live in `routes/`; endpoint request handling lives in
`controllers/AuthController.*`; application rules live in `services/`; data
records live in `models/`; database access and migrations live in
`repositories/` and `migrations/`. `error_middleware/ErrorMiddleware` normalizes
error responses and maps request exceptions to consistent JSON responses.

Request flow is: route -> `ErrorMiddleware` -> controller -> auth service ->
security utilities and repository -> SQLite. Drogon catches controller
exceptions outside the
middleware chain, so `main.cc` also forwards its exception hook to the same
error middleware. Unmatched routes use the middleware's JSON 404 response.

## Configuration

Set these environment variables before starting the backend:

| Variable | Required | Purpose |
| --- | --- | --- |
| `TASK_MANAGER_JWT_SECRET` | yes | HMAC key; use at least 32 cryptographically random bytes |
| `TASK_MANAGER_DATABASE_PATH` | no | SQLite file path; defaults to `task_manager.sqlite3` |
| `TASK_MANAGER_MIGRATIONS_DIR` | no | SQL migration directory; defaults to the build's copied migrations |
| `TASK_MANAGER_TLS_CERT` | yes | PEM certificate for the HTTPS listener |
| `TASK_MANAGER_TLS_KEY` | yes | Matching private key; protect its file permissions |
| `TASK_MANAGER_CORS_ORIGIN` | no | Exact browser origin allowed to call the auth API, e.g. `http://localhost:5000`; do not include a path or trailing slash |
| `TASK_MANAGER_LISTEN_ADDRESS` | no | Listener address; defaults to `0.0.0.0` |
| `TASK_MANAGER_PORT` | no | HTTPS port; defaults to `5555` |

Use a secret manager or protected service environment for secrets. Do not put
secrets in source files or commit them. The API listener is HTTPS-only and
startup fails if its certificate or key is missing. The process uses a
restrictive umask and restricts an existing SQLite database file to its owner.

For Flutter Web, set `TASK_MANAGER_CORS_ORIGIN` to the exact origin shown by
the Flutter development server. The API allows only that origin and handles
preflight requests for the authentication routes; it does not enable
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

A caller with a valid token who fails one of these rules gets `403 Forbidden`
(`ForbiddenError` in `services/AuthService.h`, mapped in `ErrorMiddleware`).
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
`TASK_MANAGER_CORS_ORIGIN` to the single frontend origin.
