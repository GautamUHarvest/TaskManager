# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

Monorepo with three top-level parts:

- [backend/](backend/) — C++ (Drogon) HTTPS JSON API. Implements **authentication** plus authenticated task-domain endpoints, grouped by resource like `/api/auth/*`: tasks under `/api/task/*` (`add` [POST], `all`, `mine`, `completed`), users under `/api/user/*` (`all`), notifications under `/api/notification/*` (`all`). The full request/response contract is in [apirequirement.md](apirequirement.md) (keep it in sync when changing endpoints).
- [frontend/](frontend/) — Flutter Web client (auth + profile demo), talks to the backend over HTTPS.
- [libraries/drogon/](libraries/drogon/) — vendored Drogon source. **Not** built by the backend: CMake uses `find_package(Drogon CONFIG REQUIRED)`, so a system-installed Drogon is required. The vendored copy is reference/fallback (its `add_subdirectory` wiring in [backend/CMakeLists.txt](backend/CMakeLists.txt) is commented out).

`backend/README.md` and `frontend/README.md` are accurate and detailed — read them for the full env-var table, route contract, and run instructions. This file covers only what spans multiple files.

## Backend commands (run from repo root)

```sh
# Configure + build
cmake -S backend -B backend/build
cmake --build backend/build -j2

# Local dev run: generates/reuses a JWT secret, uses dev TLS certs, builds, binds localhost
./backend/run-local.sh            # listens on https://localhost:5555, allows CORS origin http://localhost:5000

# Tests (Drogon test framework)
ctest --test-dir backend/build                                   # all
./backend/build/test/TaskManagerBackend_test -l                  # list cases
./backend/build/test/TaskManagerBackend_test -r AuthInputValidation   # single case
```

`run-local.sh` only builds an **already-configured** `backend/build`; run the `cmake -S backend -B backend/build` step first on a clean checkout.

On the Windows dev machine there is no native C++ toolchain, but the **WSL Ubuntu** distro has g++, cmake, and Drogon (in `/usr/local`), so the backend can be built and tested there — configure with a build dir outside the repo (e.g. `/tmp/tm-build`). The only missing package is the libcurl headers (needed by the dormant `SmtpMailer`); pass `-DCURL_INCLUDE_DIR=… -DCURL_LIBRARY=/usr/lib/x86_64-linux-gnu/libcurl.so.4` pointing at an unpacked `libcurl4-openssl-dev`.

## Frontend commands (run from `frontend/`)

```sh
flutter pub get
flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=https://localhost:5555
flutter test        # (no tests committed yet)
flutter analyze     # lints via flutter_lints (analysis_options.yaml)
```

The web port must be in the backend's `TASK_MANAGER_CORS_ORIGIN` allowlist (`run-local.sh` defaults it to `http://localhost:5000` plus `http://<each IPv4 of the host>`), and `API_BASE_URL` must match the backend listener.

## Backend architecture

Request flow: **`http::Router` → `ErrorMiddleware` → controller → `http::Dispatcher` (worker queue + bearer-token check) → service → repository → SQLite**. One module per resource (auth, task, project, note, comment, notification, user) at each layer; the directory map is in [backend/README.md](backend/README.md).

- **Manual wiring, no Drogon codegen.** No `METHOD_ADD` controllers and no Drogon ORM. [backend/main.cc](backend/main.cc) is the composition root: it builds config → database → repositories → services → controllers by hand. [backend/routes/ApiRoutes.cc](backend/routes/ApiRoutes.cc) is the **single route table**; `http::Router` registers each entry with `app().registerHandler(...)` and records its method, and the CORS preflight is answered from that same record — there is no separate path list to keep in sync. Adding an endpoint = repository method (if new SQL) + service method + controller handler + one line in `ApiRoutes.cc`.
- **Services take the caller, not a token.** Controllers call `dispatcher_.authenticated(request, callback, [..](const UserRecord &actor) {...})`, which verifies the token on the worker thread; services receive `actor` and never see `AuthService`. This is what lets [backend/test/RepositoryTest.cc](backend/test/RepositoryTest.cc) drive `TaskService` without issuing JWTs. Auth runs before body parsing, so a bad token wins over a bad body (401, not 400).
- **Config is env-vars only**, read once in [backend/config/AppConfig.cc](backend/config/AppConfig.cc). The Drogon `config.yaml` / `config.json` in `backend/` are unmodified examples and are **not loaded**. Startup fails fast if required secrets/TLS files are missing; the listener is HTTPS-only.
- **Errors: one header, one mapping.** Every exception type with an HTTP status lives in [backend/common/Errors.h](backend/common/Errors.h); `ErrorMiddleware` maps them. `NotFoundError` currently derives from `std::invalid_argument` and so returns **400**, matching the historical contract — switching to 404 is one branch in `ErrorMiddleware::statusFor`. There are two entry points: the middleware for matched routes, and `main.cc` forwarding `setExceptionHandler`/`setDefaultHandler` (404) to the same code. Keep both consistent.
- **Data access is raw `sqlite3` through [backend/db/Sqlite.h](backend/db/Sqlite.h)**: `Connection`, `Statement`, RAII `Transaction` (rolls back unless `commit()`ed), and `SqliteError`, which captures the extended result code *at the failing call*. Map constraint failures with `db::mapConstraintError("message", [&]{ ... })` — never read `sqlite3_errcode()` after the fact (doing so is what made a bad assignee id return 500). Repositories open a connection per call with `PRAGMA foreign_keys = ON`. Migrations are numbered SQL files in [backend/migrations/](backend/migrations/), applied by [backend/db/Migrations.cc](backend/db/Migrations.cc) at startup; add schema changes as a new numbered file.
- **Blocking work runs off the event loop.** `http::Dispatcher` runs handler bodies on a `trantor::ConcurrentTaskQueue` (named "auth-workers" for history; it serves every endpoint) because scrypt and SQLite are synchronous.
- **Build:** all sources except `main.cc` form the `taskmanager_core` **OBJECT** library (globbed with `CONFIGURE_DEPENDS`, so new `.cc` files need no cmake re-run), linked by both the server and the tests. It must stay OBJECT, not STATIC: `BlockerSocketController` registers itself via a static initializer nothing references, which a static archive would let the linker drop.
- **Tests** ([backend/test/](backend/test/)): `SecurityTest` (crypto, origins, rate limiter), `TaskRulesTest` (pure validation/permission rules), `RepositoryTest` (repositories and `TaskService` against a freshly migrated temp SQLite file).

### Two things that are easy to misread

1. **Task-domain rules live in `services/TaskRules`, not in the services.** Validation, enum defaults and the permission predicates (`canEditTask`, `canDeleteTask`) are pure functions there; the services only sequence lookups, rules, and repository calls. `project_id` has no DB foreign key (migration 006), so its existence is checked in `TaskService`; everything else relies on FK enforcement mapped to 400. The schema still has unused capacity: `tasks.version` is bumped on every write but not yet checked (no optimistic concurrency).
2. **Email verification is disabled and its code is dormant.** Migration `003_disable_email_verification.sql` activates accounts directly; `register` creates an active account. `VerificationMailer` ([backend/services/AuthService.h](backend/services/AuthService.h)) and `SmtpMailer` ([backend/services/SmtpMailer.cc](backend/services/SmtpMailer.cc)) still exist but are **not wired into `main.cc`**. The frontend README's "email verification" step is stale.

### Real-time blockers (the one deviation from manual wiring)

`POST /api/task/block` flags a task `blocked` and alerts the member held
responsible over a WebSocket at `/ws/notifications`.
[backend/controllers/BlockerSocketController](backend/controllers/BlockerSocketController.h)
is the **only** Drogon auto-registering controller in the codebase — it uses
`WS_PATH_LIST_BEGIN`/`WS_PATH_ADD` because Drogon has no non-macro WebSocket
route registration. It needs no `main.cc` registration; the vtable emitted in
its `.cc` triggers the static registrar.

- **Auth is by first message**, not header or query string:
  `{"type":"auth","access_token":"<jwt>"}`. Browsers cannot set
  `Authorization` on a WS handshake, and a token in the URL would be logged.
  Unauthenticated sockets close after 10s; `Origin` is checked against
  `TASK_MANAGER_CORS_ORIGIN` since CORS does not apply to WebSockets. That
  variable is a **comma-separated allowlist** (parsed in header-only
  [backend/security/OriginPolicy.h](backend/security/OriginPolicy.h), shared by
  all four origin checks). Behind nginx it must still list the origin users
  open the app from, or sockets upgrade and are closed straight away.
- **Token verification is dispatched to the `auth-workers` queue**, never run
  inline — it reads SQLite, and `handleNewMessage` runs on the event loop.
- [backend/services/BlockerHub](backend/services/BlockerHub.h) is a singleton
  (Drogon constructs WS controllers itself, so there is nowhere to inject);
  `main.cc` calls `configure(&auth, &authWorkers)`. Its socket map is
  **per-process**, same single-process assumption as SQLite and the rate
  limiter.
- Live push is best-effort. The stored `blocker` notification is the delivery
  guarantee, replayed via `GET /api/notification/pending-blockers` and
  dismissed with `POST /api/notification/ack`.
- **nginx needs an explicit `/ws/` location** with `Upgrade`/`Connection`
  headers — see backend/README.md. Without it the handshake fails silently and
  clients reconnect forever.

## Domain constraints to preserve

- **Email domain is enforced in two places** that must stay in sync: SQLite triggers in `002_authentication.sql` (`@uharvest.in` only) and `security::validEmail`. Changing the allowed domain requires updating both.
- Password rules (`security::validPassword`): currently min 6 chars with uppercase + number + special. The README flags 12+ as the pre-production target.
- Registration is capped at 25 active accounts (`UserLimitError`). IP rate limits are in-process memory only — they reset on restart and assume a **single** backend process against the SQLite file.

## Frontend architecture

- Entry [frontend/lib/main.dart](frontend/lib/main.dart) wires `AuthController(AuthApi())` and swaps between `AuthScreen` and `ProfileScreen` based on `controller.isAuthenticated` via `AnimatedBuilder` (the controller is a `ChangeNotifier`).
- [frontend/lib/auth/auth_api.dart](frontend/lib/auth/auth_api.dart) is the only networking layer; base URL comes from the `API_BASE_URL` dart-define. JSON field names are snake_case to match the backend.
- Token storage uses the **localStorage refresh-token model**: the access token stays in memory (short-lived, 10 min), but the **refresh token is persisted in `localStorage`** so a reload can resurrect the session. This was a deliberate switch away from the earlier HttpOnly-cookie model so the app works over plain HTTP on a LAN/demo box — at the cost of XSS exposure of the refresh token. See the security note in [apirequirement.md](apirequirement.md) §2. For production, prefer the cookie model over HTTPS.
