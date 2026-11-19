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
| `TASK_MANAGER_REFRESH_COOKIE_SAMESITE` | no | `SameSite` attribute on the refresh cookie. One of `Strict`, `Lax`, `None`; defaults to `Strict`. Use `None` when the frontend and backend are on different schemes (e.g. dev `http://localhost:5000` → `https://localhost:5555`), because Chrome's schemeful same-site treats them as cross-site and would silently drop the cookie |
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
| `POST /api/auth/login` | `login` (employee ID or email), `password` | Returns the access token in the JSON body and sets the refresh token as an HttpOnly cookie |
| `POST /api/auth/refresh` | _(no body; the `refresh_token` HttpOnly cookie is the credential)_ | Rotates the refresh cookie and issues a new access token |
| `POST /api/auth/logout` | Bearer access token | Revokes its refresh session, clears the refresh cookie; any issued access token expires within 10 minutes |
| `GET /api/auth/me` | Bearer access token | Returns the authenticated user's profile |

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

Refresh tokens are issued **only** as an `HttpOnly; Secure; SameSite=Strict;
Path=/api/auth` cookie named `refresh_token`. They are not in the JSON body
and JavaScript cannot read them. `POST /api/auth/login` and
`POST /api/auth/refresh` set a fresh cookie (the server rotates the token on
every call and overwrites the cookie with the replacement);
`POST /api/auth/logout` clears it. Browser clients must opt into sending
cookies (`credentials: 'include'` on `fetch`, `withCredentials = true` on XHR,
`BrowserClient()..withCredentials = true` on Flutter Web); native clients
must send and persist the cookie themselves. Keep access tokens in memory
only and never put bearer tokens in URLs or application logs.

Because cookies are credentials, CORS responses include
`Access-Control-Allow-Credentials: true` and the allowlisted origin must be
exact — wildcard origins are refused by the browser when credentials are in
play. Set `TASK_MANAGER_CORS_ORIGIN` to the single frontend origin.
