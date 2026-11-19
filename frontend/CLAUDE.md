# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter **Web** app (`task_manager_frontend`) for Task Manager: account registration, sign-in, and an authenticated profile, wrapped in a task-workspace shell. Targets Material Design 3. The backend is a **separate HTTPS service not in this tree** (the sibling `TaskManager/` folder is empty); this repo is the frontend only.

## Commands

Run from the `TaskManagerUI/` directory (the Flutter project root, where `pubspec.yaml` lives):

```sh
flutter pub get                                  # fetch dependencies
flutter run -d chrome \                          # dev server
  --web-port=5000 \
  --dart-define=API_BASE_URL=https://localhost:5555
flutter analyze                                  # lint (flutter_lints via analysis_options.yaml)
flutter test                                      # all tests
flutter test test/task_workspace_screen_test.dart          # single file
flutter test --plain-name 'navigation starts closed'       # single test by name
flutter build web                                 # production build
```

`API_BASE_URL` is read at build/run time via `--dart-define` (default `/api`). The backend's `TASK_MANAGER_CORS_ORIGIN` must exactly match the dev-server origin (e.g. `http://localhost:5000`) — it uses an exact-origin allowlist, not a wildcard. The backend TLS cert must be valid and browser-trusted; **do not disable TLS verification** in the app.

## Architecture

**UI import convention (important):** all widgets are imported from `package:material_ui/material_ui.dart` (pub package `material_ui`, which re-exports Flutter's Material library), **not** from `package:flutter/material.dart`. New UI files must follow this. `package:flutter/foundation.dart` is still imported directly where needed (e.g. `ChangeNotifier`).

**App wiring ([lib/main.dart](lib/main.dart)):** `main()` builds one shared `ApiClient`, wraps it in `AuthApi` + `DataApi`, hands both to a single `AuthController`, and passes that down. `TaskManagerApp` wraps the root in an `AnimatedBuilder` listening to the controller and swaps the whole screen on `controller.isAuthenticated`: `AuthScreen` when signed out, `TaskWorkspaceScreen` when signed in. There is no router.

**State management:** plain `ChangeNotifier` ([lib/auth/auth_controller.dart](lib/auth/auth_controller.dart)) observed via `AnimatedBuilder`/`FutureBuilder`. No provider/bloc/riverpod — keep this pattern.

**Three API layers — all calls go through the controller, never `http` from a widget:**
- [lib/api/api_client.dart](lib/api/api_client.dart) — `ApiClient` is the only place that knows the base URL, JSON encoding, optional `Authorization: Bearer` header, and error decoding. It also owns `AuthApiException` (re-exported from `auth_api.dart` for existing call sites). The wire contract is **snake_case** throughout; non-2xx responses carry `json['error']`.
- [lib/auth/auth_api.dart](lib/auth/auth_api.dart) — `/auth/{register,login,refresh,me,logout}`. Models `AuthUser`, `AuthTokens`.
- [lib/tasks/data_api.dart](lib/tasks/data_api.dart) — Bearer-protected `/task/{add,all,mine,completed}`, `/user/all`, `/notification/all`. Models + `TaskStatus` enum in [lib/tasks/task_models.dart](lib/tasks/task_models.dart).
- `AuthController` holds the tokens and exposes the typed methods (`login/loadProfile/logout`, `myTasks/allTasks/completedTasks/createTask/allUsers/notifications`). **Every Bearer call routes through its private `_authorized<T>()` wrapper**, which supplies the access token, refreshes proactively before expiry, and retries once on a `401`. New data endpoints should be added as `DataApi` methods + a thin `_authorized(...)` method on the controller — do not thread tokens through widgets.

**Real-time blocker alerts ([lib/realtime/blocker_socket.dart](lib/realtime/blocker_socket.dart)):** `BlockerSocket` wraps a `dart:html` WebSocket at `/ws/notifications` (URL derived from `API_BASE_URL`, `https`→`wss`). It authenticates by sending `{"type":"auth","access_token":...}` as its **first frame** — a browser cannot set an `Authorization` header on a WS handshake, and a token in the query string would be logged. It pings every 30s and reconnects with capped exponential backoff, re-reading the token each attempt (it rotates). `AuthController` owns the socket: `_startBlockerChannel()` from `_setTokens` (idempotent), `_stopBlockerChannel()` from `_clearTokens`. Both the live push and the offline replay from `/notification/pending-blockers` are funnelled into one `controller.blockerAlerts` broadcast stream, deduped by notification id. `TaskWorkspaceScreen` drains that stream one alert at a time into a modal that cannot be dismissed except by OK (`barrierDismissible: false` + `PopScope(canPop: false)`), then calls `/notification/ack`. A failed ack is deliberately left unacknowledged — it replays next connect, which is the safe direction.

**`TaskStatus`** has exactly five wire values — `todo`, `in_progress`, `blocked`, `done`, `cancelled` — mapped to display labels in [lib/tasks/task_models.dart](lib/tasks/task_models.dart). Use the enum (and `TaskStatus.fromWire`) everywhere; never hard-code status strings in the UI.

**Token lifecycle (by design):** the **access token lives in memory only** (short-lived, 10 min, `expires_in` 600), while the **refresh token is persisted in `localStorage`** ([token_storage.dart](lib/auth/token_storage.dart)) so a page reload resurrects the session via `AuthController.restore()`. The refresh token **rotates on every use** — always persist the new one from a refresh response (`_setTokens` does this). The controller refreshes when within 30s of expiry (`_refreshIfExpiring`) and retries once on a `401`. **SECURITY NOTE:** a refresh token in `localStorage` is readable by JS (XSS-exposed) — a deliberate tradeoff so the app works over plain HTTP; the earlier design used an HttpOnly cookie. No cookies are used now, so `ApiClient` sets `withCredentials = false`.

**Workspace ([lib/screens/task_workspace_screen.dart](lib/screens/task_workspace_screen.dart)):** the signed-in shell loads the user directory + notification count once on `initState` (for assignee labels and the bell badge), and each section pane (`_DashboardPane`, `_TaskListPane`, `_TeamPane`, `_CreateTaskPane`) is a `StatefulWidget` that fetches through the controller in its own `initState` with loading / error-retry / empty / data states. Panes carry a `ValueKey` so switching sections recreates state and refetches. Create Task posts to `/task/add` and then routes to All Tasks.

**Client-side validation mirrors the backend** ([lib/screens/auth_screen.dart](lib/screens/auth_screen.dart)): company email must match `@uharvest.in`, employee ID matches `^[A-Za-z0-9._-]{1,64}$`, password is 6+ chars with an uppercase letter, a digit, and a symbol. These are convenience checks — the backend re-validates — so keep the two in sync when either changes.
