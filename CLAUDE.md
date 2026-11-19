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

## Frontend commands (run from `frontend/`)

```sh
flutter pub get
flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=https://localhost:5555
flutter test        # (no tests committed yet)
flutter analyze     # lints via flutter_lints (analysis_options.yaml)
```

The web port must match the backend's `TASK_MANAGER_CORS_ORIGIN` (defaults to `http://localhost:5000`), and `API_BASE_URL` must match the backend listener.

## Backend architecture

Request flow: **route → `ErrorMiddleware` → controller → `AuthService` → `security` + `AuthRepository` → SQLite**.

- **Manual wiring, no Drogon codegen.** There are no `METHOD_ADD`/auto-registered controllers and no Drogon ORM. [backend/main.cc](backend/main.cc) constructs the repository, service, and controller by hand and calls `registerAuthRoutes` ([backend/routes/AuthRoutes.cc](backend/routes/AuthRoutes.cc)), which registers each handler with `app().registerHandler(...)`. Adding an endpoint means editing a route file, a controller method, and a service method — not adding an annotation.
- **Config is env-vars only.** The Drogon `config.yaml` / `config.json` in `backend/` are the unmodified Drogon examples and are **not loaded**. All runtime config comes from `TASK_MANAGER_*` environment variables read in `main.cc` (see backend README table). Startup fails fast if required secrets/TLS files are missing; the listener is HTTPS-only.
- **Error handling has two entry points.** `ErrorMiddleware` normalizes errors for matched routes; Drogon catches exceptions thrown *outside* the middleware chain, so `main.cc` also forwards `setExceptionHandler` and `setDefaultHandler` (404) to the same `ErrorMiddleware`. Keep both paths consistent when changing error shapes.
- **Data access is raw `sqlite3`** ([backend/repositories/AuthRepository.cc](backend/repositories/AuthRepository.cc)), not Drogon's DB layer. Migrations are numbered SQL files in [backend/migrations/](backend/migrations/), applied once in order on startup; CMake copies them into the build dir and bakes the path into `TASK_MANAGER_MIGRATIONS_DIR`. Add schema changes as a new numbered file.
- **Blocking work runs off the event loop.** Controllers dispatch to a `trantor::ConcurrentTaskQueue` ("auth-workers") because password hashing (scrypt) and SQLite calls are synchronous.
- **Security primitives** live in [backend/security/AuthCrypto.cc](backend/security/AuthCrypto.cc): scrypt password hashing, HS256 access tokens (10-min expiry), random refresh tokens (rotated, only SHA-256 hashes stored), and input validation. The test suite ([backend/test/test_main.cc](backend/test/test_main.cc)) covers these directly.

### Two things that are easy to misread

1. **Auth + task reads are implemented; writes are not, and the schema is the whole app.** Migration `001_initial_schema.sql` defines `tasks`, `task_notes`, `task_events`, and `notifications` — the full task-manager domain. The Task stack ([models/Task.h](backend/models/Task.h), [repositories/TaskRepository.cc](backend/repositories/TaskRepository.cc), [services/TaskService.cc](backend/services/TaskService.cc), [controllers/TaskController.cc](backend/controllers/TaskController.cc), [routes/TaskRoutes.cc](backend/routes/TaskRoutes.cc)) serves the list reads plus `POST /api/addtask` (create). There is still no update/delete/status-change, no `task_notes`/`task_events` handling, and notifications are read but never written. Note `TaskRepository`'s `Connection` enables `PRAGMA foreign_keys = ON`, so create relies on FK enforcement (bad `assignee_id`/`parent_task_id` → `SQLITE_CONSTRAINT` → mapped to 400). The Task stack **intentionally duplicates** the Auth stack's SQLite `Connection`/`Statement` helpers and the controller's `bearerToken`/`jsonResponse`/`run` helpers — a modularity refactor to share them is planned. `TaskService` authenticates by calling `AuthService::profile(token)`. The schema already anticipates subtasks (`parent_task_id`), optimistic concurrency (`tasks.version`), an event log, and notifications.
2. **Email verification is disabled and its code is dormant.** Migration `003_disable_email_verification.sql` activates accounts directly; `register` creates an active account. `VerificationMailer` ([backend/services/AuthService.h](backend/services/AuthService.h)) and `SmtpMailer` ([backend/services/SmtpMailer.cc](backend/services/SmtpMailer.cc)) still exist but are **not wired into `main.cc`**. The frontend README's "email verification" step is stale.

## Domain constraints to preserve

- **Email domain is enforced in two places** that must stay in sync: SQLite triggers in `002_authentication.sql` (`@uharvest.in` only) and `security::validEmail`. Changing the allowed domain requires updating both.
- Password rules (`security::validPassword`): currently min 6 chars with uppercase + number + special. The README flags 12+ as the pre-production target.
- Registration is capped at 25 active accounts (`UserLimitError`). IP rate limits are in-process memory only — they reset on restart and assume a **single** backend process against the SQLite file.

## Frontend architecture

- Entry [frontend/lib/main.dart](frontend/lib/main.dart) wires `AuthController(AuthApi())` and swaps between `AuthScreen` and `ProfileScreen` based on `controller.isAuthenticated` via `AnimatedBuilder` (the controller is a `ChangeNotifier`).
- [frontend/lib/auth/auth_api.dart](frontend/lib/auth/auth_api.dart) is the only networking layer; base URL comes from the `API_BASE_URL` dart-define. JSON field names are snake_case to match the backend.
- Token storage uses the **localStorage refresh-token model**: the access token stays in memory (short-lived, 10 min), but the **refresh token is persisted in `localStorage`** so a reload can resurrect the session. This was a deliberate switch away from the earlier HttpOnly-cookie model so the app works over plain HTTP on a LAN/demo box — at the cost of XSS exposure of the refresh token. See the security note in [apirequirement.md](apirequirement.md) §2. For production, prefer the cookie model over HTTPS.
