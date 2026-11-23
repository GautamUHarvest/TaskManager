# Task Manager — API Requirements (Frontend Integration)

> **⚠️ SUPERSEDED — do not use this file.**
> The authoritative API contract is [`../apirequirement.md`](../apirequirement.md)
> at the repository root. This copy is stale: it still describes an
> HttpOnly-cookie refresh model that was reverted (auth now returns the refresh
> token in the JSON body), and it predates projects, threaded comments,
> multi-assignee tasks, and the edit/delete endpoints.
> Delete this file once nothing links to it.

This document lists every HTTP endpoint the backend exposes, the request data each
needs, and the exact JSON each returns. It is the contract the Flutter frontend
integrates against.

_Last updated: 2026-11-16._

---

## 1. Base URL

| Context | Base URL | Notes |
| --- | --- | --- |
| Production (served by nginx) | `/api` (relative) | Same origin as the web app; nginx proxies `/api/*` to the backend. **No cert/CORS issues.** |
| Direct local dev (`flutter run`) | `https://<host>:5555/api` | Hits the backend's TLS port directly; needs the dev cert trusted and a matching `TASK_MANAGER_CORS_ORIGIN`. |

The Flutter client stores the base in `API_BASE_URL` (default `/api`) and appends
paths **without** a leading `/api` (e.g. the client calls `/auth/login`, which
resolves to `/api/auth/login`). All paths below are shown in full from the host
root.

## 2. Conventions

- **Content type:** all request and response bodies are JSON (`Content-Type: application/json`), except `POST /api/auth/logout` and `POST /api/auth/refresh` (no body) and `204` responses (empty).
- **Field naming:** `snake_case` everywhere.
- **Auth:** protected endpoints require the header `Authorization: Bearer <access_token>`.
- **Access token lifetime:** 10 minutes (`expires_in` = `600`). Use `POST /api/auth/refresh` to get a new one; the refresh token rotates on every call.
- **Refresh token storage:** the refresh token is delivered **only** in an `HttpOnly; Secure; SameSite=Strict; Path=/api/auth` cookie named `refresh_token`. It is never in the JSON body and JavaScript cannot read it. The browser must send cookies on `/api/auth/*` requests (`credentials: 'include'` on `fetch`, or `withCredentials = true` on XHR / Flutter Web `BrowserClient`). `POST /api/auth/login` and `POST /api/auth/refresh` both return a fresh `Set-Cookie: refresh_token=...` header; `POST /api/auth/logout` clears it.
- **Access token storage (client):** keep the access token in memory only (cleared on reload). Do not put it in URLs or logs.
- **CORS with credentials:** cross-origin responses to the exact allowed origin include `Access-Control-Allow-Credentials: true`. Preflight for `/api/auth/*` includes the same. Wildcard origins are **not** allowed when credentials are in play.
- **Error shape:** every non-2xx response is `{ "error": "<human-readable message>" }`.
- All responses send `Cache-Control: no-store`.

### Common error codes

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | A field is missing, the wrong type, or fails validation. |
| `401 Unauthorized` | Missing/invalid/expired access token, or wrong credentials. |
| `409 Conflict` | Duplicate employee ID/email, or the 25-active-user cap is reached. |
| `429 Too Many Requests` | Per-IP rate limit hit (register: 20/hour, login: 60/min). |
| `500 Internal Server Error` | Unexpected server error. |

## 3. Shared object shapes

**user**
```json
{ "id": 1, "employee_id": "EMP-001", "email": "person@uharvest.in", "display_name": "Person Name" }
```

**task** (nullable fields come back as JSON `null`)
```json
{
  "id": 12,
  "parent_task_id": null,
  "title": "Write Q4 report",
  "description": "Draft and circulate",
  "status": "in_progress",
  "type": "design",
  "discipline": "mechanical",
  "due_at": "2026-12-01T09:00:00Z",
  "start_at": "2026-11-20T09:00:00Z",
  "index": 21,
  "assignee_id": 1,
  "created_by_id": 1,
  "version": 1,
  "created_at": "2026-11-16T10:52:37.433Z",
  "updated_at": "2026-11-16T10:52:37.433Z"
}
```
`index` is the task's position within its project (1–1,000,000); see the root `apirequirement.md` for the full rules.
`status` is always one of: `todo`, `in_progress`, `blocked`, `done`, `cancelled`.

`type` is one of: `design`, `test`, `decide`, `measure`, `select`, `buy`, `admin`, `code`, `make`, `data`, `doc`, `integrate`, `plan`, `review`. Defaults to `decide` ("to be decided") when omitted.

`discipline` is one of: `mechanical`, `electronics`, `software`, `server_backend`, `communications`, `embedded`, `control_systems`, `project_management`, `operations`, `payments`, `systems_integration`, `frontend`, `decide`. Defaults to `decide` when omitted.

**note** (a task note)
```json
{
  "id": 1,
  "task_id": 12,
  "author_id": 1,
  "body": "Draft sent for review",
  "created_at": "2026-11-16T10:52:37.447Z",
  "updated_at": "2026-11-16T10:52:37.447Z"
}
```

**notification**
```json
{
  "id": 5,
  "recipient_id": 1,
  "actor_id": 2,
  "task_id": 12,
  "notification_type": "assigned",
  "message": "You were assigned \"Write Q4 report\"",
  "created_at": "2026-11-16T10:52:37.447Z",
  "read_at": null
}
```

**tokens** (returned by login and refresh)
```json
{
  "access_token": "<jwt>",
  "token_type": "Bearer",
  "expires_in": 600,
  "user": { "...": "user object" }
}
```
The refresh token is **not** in this body. It is set as an `HttpOnly; Secure;
SameSite=Strict; Path=/api/auth; Max-Age=2592000` cookie named `refresh_token`
via a `Set-Cookie` header on the same response.

---

## 4. Endpoints

### Authentication

#### `POST /api/auth/register`
Create an active account (no email verification). Auth: **none**.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `employee_id` | string | yes | Non-empty, no surrounding spaces. Unique. |
| `email` | string | yes | Must be a valid **`@uharvest.in`** address. Unique. |
| `display_name` | string | yes | 1–100 characters. |
| `password` | string | yes | ≥ 6 chars, with at least one uppercase letter, one number, and one special character. |

Request:
```json
{ "employee_id": "EMP-001", "email": "person@uharvest.in", "display_name": "Person Name", "password": "Good!Pass1" }
```
Success `201 Created`:
```json
{ "message": "Account created. You can now sign in", "user_id": 1 }
```
Errors: `400` (validation), `409` (duplicate or 25-user cap), `429`.

---

#### `POST /api/auth/login`
Exchange credentials for tokens. Auth: **none**.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `login` | string | yes | Employee ID **or** email. |
| `password` | string | yes | — |

Request:
```json
{ "login": "EMP-001", "password": "Good!Pass1" }
```
Success `200 OK`: a **tokens** object (see §3).
Errors: `401` (invalid credentials), `400`, `429`.

---

#### `POST /api/auth/refresh`
Rotate the refresh token and get a new access token. Auth: **cookie** — the browser must send the `refresh_token` HttpOnly cookie that was set by `POST /api/auth/login` (or by a previous refresh). The cookie is the only credential; **there is no request body**.

Request: *(no body; the cookie is sent automatically with `credentials: 'include'`)*

Success `200 OK`: a **tokens** object. The response also carries a **new** `Set-Cookie: refresh_token=...` header — the previous refresh token is now invalid and the browser has already been given its replacement, so no client code needs to touch it.
Errors: `401` (missing/invalid/expired/already-rotated refresh cookie), `400`.

---

#### `POST /api/auth/logout`
Revoke the current session. Auth: **Bearer**. **No request body.**

Success `204 No Content` (empty body). The response clears the `refresh_token` cookie (`Set-Cookie: refresh_token=; Max-Age=0; Path=/api/auth`).
Errors: `401`.

---

#### `GET /api/auth/me`
Return the authenticated user's profile. Auth: **Bearer**.

Success `200 OK`:
```json
{ "user": { "...": "user object" } }
```
Errors: `401`.

---

### Tasks & data

#### `POST /api/task/add`
Create a new task. Auth: **Bearer**. `created_by_id` is taken from the token (not the body).

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `title` | string | **yes** | 1–200 characters (trimmed). |
| `description` | string | no | Up to 4000 chars; blank/omitted → `null`. |
| `status` | string | no | One of `todo`, `in_progress`, `blocked`, `done`, `cancelled`. Defaults to `todo`. |
| `type` | string | no | One of the `type` enum values (see §3). Defaults to `decide`. |
| `discipline` | string | no | One of the `discipline` enum values (see §3). Defaults to `decide`. |
| `due_at` | string | no | Timestamp string (ISO-8601 recommended, e.g. `2026-12-01T09:00:00Z`). |
| `start_at` | string | no | Start-date timestamp (ISO-8601 recommended). |
| `assignee_id` | integer | no | Must be an existing active user id, else `400`. |
| `parent_task_id` | integer | no | Must be an existing task id (for subtasks), else `400`. |

Minimal request:
```json
{ "title": "Write Q4 report" }
```
Full request:
```json
{
  "title": "Write Q4 report",
  "description": "Draft and circulate",
  "status": "in_progress",
  "type": "design",
  "discipline": "mechanical",
  "due_at": "2026-12-01T09:00:00Z",
  "start_at": "2026-11-20T09:00:00Z",
  "assignee_id": 1,
  "parent_task_id": null
}
```
Success `201 Created`:
```json
{ "task": { "...": "task object (with server-assigned id, timestamps, version)" } }
```
Errors: `400` (missing/invalid field, bad status, non-existent assignee/parent), `401`.

---

#### `POST /api/task/subtask`
Create a subtask under an existing parent task. Auth: **Bearer**. `created_by_id` is taken from the token. Same fields as `POST /api/task/add`, except **`parent_task_id` is required**. Records a `subtask_created` event on the parent task.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `parent_task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `title` | string | **yes** | 1–200 characters (trimmed). |
| `description` | string | no | Up to 4000 chars; blank/omitted → `null`. |
| `status` | string | no | One of the five statuses. Defaults to `todo`. |
| `type` | string | no | One of the `type` enum values (see §3). Defaults to `decide`. |
| `discipline` | string | no | One of the `discipline` enum values (see §3). Defaults to `decide`. |
| `due_at` | string | no | Timestamp string (ISO-8601 recommended). |
| `start_at` | string | no | Start-date timestamp (ISO-8601 recommended). |
| `assignee_id` | integer | no | Must be an existing active user id, else `400`. |

Request:
```json
{ "parent_task_id": 12, "title": "Draft section 1", "status": "in_progress", "type": "design", "discipline": "mechanical" }
```
Success `201 Created`:
```json
{ "task": { "...": "task object (with parent_task_id set, server-assigned id, timestamps, version)" } }
```
Errors: `400` (missing/invalid field, bad status, non-existent parent/assignee), `401`.

---

#### `POST /api/task/note`
Add a free-text note to an existing task. Auth: **Bearer**. `author_id` is taken from the token (not the body).

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `body` | string | **yes** | 1–4000 characters (trimmed); blank → `400`. |

Request:
```json
{ "task_id": 12, "body": "Draft sent for review" }
```
Success `201 Created`:
```json
{
  "message": "Note created",
  "note": { "id": 7, "task_id": 12, "author_id": 3, "body": "Draft sent for review", "created_at": "2026-11-17T10:52:37.447Z", "updated_at": "2026-11-17T10:52:37.447Z" }
}
```
Errors: `400` (missing/invalid field, non-existent task), `401`.

---

#### `POST /api/task/status`
Change an existing task's status. Auth: **Bearer**. Bumps the task's `version`, refreshes `updated_at`, and records a `status_changed` event.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `status` | string | **yes** | One of `todo`, `in_progress`, `blocked`, `done`, `cancelled`. |

Request:
```json
{ "task_id": 12, "status": "blocked" }
```
Success `200 OK`:
```json
{ "task": { "...": "task object (with new status and incremented version)" } }
```
Errors: `400` (missing/invalid field, bad status value, non-existent task), `401`.

---

#### `GET /api/user/all`
List all active users (for assignee pickers). Auth: **Bearer**.

Success `200 OK`:
```json
{ "users": [ { "...": "user object" } ] }
```
Errors: `401`.

---

#### `GET /api/task/all`
List every task, grouped by project and in `index` order within each project. Auth: **Bearer**.

Success `200 OK`:
```json
{ "tasks": [ { "...": "task object" } ] }
```
Errors: `401`.

---

#### `GET /api/task/mine`
List tasks assigned to the authenticated user (ordered by due date, then newest). Auth: **Bearer**.

Success `200 OK`:
```json
{ "tasks": [ { "...": "task object" } ] }
```
Errors: `401`.

---

#### `GET /api/task/completed`
List tasks with status `done`, most recently updated first. Auth: **Bearer**.

Success `200 OK`:
```json
{ "tasks": [ { "...": "task object" } ] }
```
Errors: `401`.

---

#### `GET /api/task/detail`
Return a single task together with its direct subtasks and its notes — for a task detail view. Auth: **Bearer**. The task id is passed as a **query parameter**, `task_id`.

| Query param | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | A positive existing task id. Missing/non-integer → `400`; unknown id → `400`. |

Request: `GET /api/task/detail?task_id=12`

Success `200 OK`:
```json
{
  "task": { "...": "task object" },
  "subtasks": [ { "...": "task object (direct children, parent_task_id = task.id)" } ],
  "notes": [ { "...": "note object (see §3)" } ]
}
```
`subtasks` are **direct children only** (one level, not recursive), oldest first; `notes` are oldest first. Both are `[]` when there are none.
Errors: `400` (missing/invalid `task_id`, or task not found), `401`.

---

#### `GET /api/notification/all`
List the authenticated user's notifications, newest first. Auth: **Bearer**.

Success `200 OK`:
```json
{ "notifications": [ { "...": "notification object" } ] }
```
Errors: `401`.

---

## 5. Quick reference

| Method | Path | Auth | Body |
| --- | --- | --- | --- |
| POST | `/api/auth/register` | — | `employee_id`, `email`, `display_name`, `password` |
| POST | `/api/auth/login` | — | `login`, `password` → sets `refresh_token` HttpOnly cookie |
| POST | `/api/auth/refresh` | `refresh_token` cookie | _(none)_ → rotates the cookie |
| POST | `/api/auth/logout` | Bearer | _(none)_ → clears the cookie |
| GET | `/api/auth/me` | Bearer | — |
| POST | `/api/task/add` | Bearer | `title`(+ optional `description`, `status`, `due_at`, `assignee_id`, `parent_task_id`) |
| POST | `/api/task/subtask` | Bearer | `parent_task_id`, `title`(+ optional `description`, `status`, `due_at`, `assignee_id`) |
| POST | `/api/task/note` | Bearer | `task_id`, `body` |
| POST | `/api/task/status` | Bearer | `task_id`, `status` |
| GET | `/api/task/all` | Bearer | — |
| GET | `/api/task/mine` | Bearer | — |
| GET | `/api/task/completed` | Bearer | — |
| GET | `/api/task/detail` | Bearer | query `task_id` → `{ task, subtasks, notes }` |
| GET | `/api/user/all` | Bearer | — |
| GET | `/api/notification/all` | Bearer | — |

## 6. Not yet implemented (planned)

- Update/delete task, assign/reassign, due-date changes.
- Reading the task event history. `task_events` is **written** by
  `POST /api/task/subtask` and `POST /api/task/status`, but there is no endpoint
  to read it. (A task's notes and direct subtasks are now readable via
  `GET /api/task/detail`.)
- Optimistic concurrency on status change (no client-supplied expected `version`).
- Writing notifications (they are currently only read) and marking them read.
