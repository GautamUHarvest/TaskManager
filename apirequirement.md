# Task Manager — API Requirements (Frontend Integration)

This document lists every HTTP endpoint the backend exposes, the request data each
needs, and the exact JSON each returns. It is the contract the Flutter frontend
integrates against.

_Last updated: 2026-11-18._

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

- **Content type:** all request and response bodies are JSON (`Content-Type: application/json`), except `POST /api/auth/logout` (no body) and `204` responses (empty).
- **Field naming:** `snake_case` everywhere.
- **Auth:** protected endpoints require the header `Authorization: Bearer <access_token>`.
- **Access token lifetime:** 10 minutes (`expires_in` = `600`). Use `POST /api/auth/refresh` to get a new one; the refresh token rotates on every call.
- **Refresh token storage:** the refresh token is returned in the JSON body of `POST /api/auth/login` and `POST /api/auth/refresh` (field `refresh_token`). The client stores it (localStorage) and sends it in the `POST /api/auth/refresh` request body. No cookies are used. **SECURITY NOTE:** a refresh token in localStorage is readable by JavaScript and therefore exposed to XSS; this model is a deliberate tradeoff so the app works over plain HTTP on a LAN/demo deployment. For production, prefer the HttpOnly-cookie model served over HTTPS.
- **Access token storage (client):** keep the access token in memory only (cleared on reload). Do not put it in URLs or logs.
- **CORS with credentials:** cross-origin responses to the exact allowed origin include `Access-Control-Allow-Credentials: true`. Preflight for `/api/auth/*` includes the same. Wildcard origins are **not** allowed when credentials are in play.
- **Error shape:** every non-2xx response is `{ "error": "<human-readable message>" }`.
- All responses send `Cache-Control: no-store`.

### Common error codes

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | A field is missing, the wrong type, or fails validation. |
| `401 Unauthorized` | Missing/invalid/expired access token, or wrong credentials. |
| `403 Forbidden` | Authenticated, but not allowed to edit/delete this record (see §4 "Editing and deleting"). |
| `409 Conflict` | Duplicate employee ID/email, or the 25-active-user cap is reached. |
| `429 Too Many Requests` | Per-IP rate limit hit (register: 20/hour, login: 60/min). |
| `500 Internal Server Error` | Unexpected server error. |

## 3. Shared object shapes

**user**
```json
{ "id": 1, "employee_id": "EMP-001", "email": "person@uharvest.in", "display_name": "Person Name" }
```

**project**
```json
{
  "id": 2,
  "name": "Apollo",
  "description": "Rocket programme",
  "created_by_id": 1,
  "created_at": "2026-11-18T10:52:37.433Z",
  "updated_at": "2026-11-18T10:52:37.433Z"
}
```
Project `id` `1` is the built-in **"Unidentified"** project; its `created_by_id` is `null` (system-owned, no human creator). For user-created projects `created_by_id` is the creator's user id. Every task belongs to exactly one project; tasks created without a `project_id` fall under project `1`.

**task** (nullable fields come back as JSON `null`)
```json
{
  "id": 12,
  "parent_task_id": null,
  "project_id": 1,
  "title": "Write Q4 report",
  "description": "Draft and circulate",
  "status": "in_progress",
  "type": "design",
  "discipline": "mechanical",
  "due_at": "2026-12-01T09:00:00Z",
  "start_at": "2026-11-20T09:00:00Z",
  "assignee_ids": [1, 3],
  "created_by_id": 1,
  "version": 1,
  "created_at": "2026-11-16T10:52:37.433Z",
  "updated_at": "2026-11-16T10:52:37.433Z"
}
```
`assignee_ids` is an array of user ids (a task can have **zero or more** assignees); it is `[]` when the task is unassigned. `project_id` is always present and non-null.
`status` is always one of: `todo`, `in_progress`, `blocked`, `done`, `cancelled`.

`type` is one of: `design`, `test`, `decide`, `measure`, `select`, `buy`, `admin`, `code`, `make`, `data`, `doc`, `integrate`. Defaults to `decide` ("to be decided") when omitted.

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

**comment** (a threaded task comment)
```json
{
  "id": 7,
  "task_id": 12,
  "author_id": 3,
  "parent_comment_id": null,
  "body": "Looks good, shipping it",
  "created_at": "2026-11-18T10:52:37.447Z",
  "updated_at": "2026-11-18T10:52:37.447Z"
}
```
`parent_comment_id` is `null` for a top-level comment, or the id of the comment being replied to. Replies form a tree; the frontend renders nesting (indentation) by following `parent_comment_id`.

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
`notification_type` values include `assigned` and `comment` (a new comment on a task the recipient is assigned to, or — for a reply — a comment the recipient wrote that was replied to).

**tokens** (returned by login and refresh)
```json
{
  "access_token": "<jwt>",
  "refresh_token": "<opaque>",
  "token_type": "Bearer",
  "expires_in": 600,
  "user": { "...": "user object" }
}
```
The `refresh_token` is an opaque string (30-day lifetime) that rotates on every
refresh. The client persists it (localStorage) and must replace its stored copy
with the new one returned by each refresh. See the security note in §2.

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
Rotate the refresh token and get a new access token. Auth: **the refresh token in the request body** (no cookie, no Bearer header).

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `refresh_token` | string | yes | The stored refresh token from the last login/refresh. |

Request:
```json
{ "refresh_token": "<opaque>" }
```
Success `200 OK`: a **tokens** object (see §3) carrying a **new** `refresh_token` — the one just sent is now invalid, so the client must persist the new one in its place.
Errors: `401` (missing/invalid/expired/already-rotated refresh token), `400`.

---

#### `POST /api/auth/logout`
Revoke the current session. Auth: **Bearer**. **No request body.**

Success `204 No Content` (empty body). The client discards its stored refresh token.
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
| `assignee_ids` | integer[] | no | Array of existing active user ids (a task may have several assignees). Duplicates are de-duplicated; each must exist or `400`. A single integer is also accepted. Omitted/empty → unassigned. |
| `parent_task_id` | integer | no | Must be an existing task id (for subtasks), else `400`. |
| `project_id` | integer | no | Must be an existing project id, else `400`. Omitted → the default "Unidentified" project (`1`). |

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
  "assignee_ids": [1, 3],
  "parent_task_id": null,
  "project_id": 2
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
| `assignee_ids` | integer[] | no | Array of existing active user ids. A single integer is also accepted. Omitted/empty → unassigned. |
| `project_id` | integer | no | Must be an existing project id, else `400`. Omitted → the default "Unidentified" project (`1`). |

Request:
```json
{ "parent_task_id": 12, "title": "Draft section 1", "status": "in_progress", "type": "design", "discipline": "mechanical", "assignee_ids": [1, 3] }
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

#### `POST /api/task/comment`
Add a comment, or a threaded reply, to an existing task. Auth: **Bearer**. `author_id` is taken from the token. **Every assignee of the task receives a `comment` notification; on a reply, the author of the parent comment is also notified even if they are not assigned.** The comment's own author is never notified, and each recipient is notified at most once.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `body` | string | **yes** | 1–4000 characters (trimmed); blank → `400`. |
| `parent_comment_id` | integer | no | Id of the comment being replied to (for nesting). Must exist **and belong to the same task**, else `400`. Omitted → a top-level comment. |

Request (top-level):
```json
{ "task_id": 12, "body": "Looks good, shipping it" }
```
Request (reply):
```json
{ "task_id": 12, "parent_comment_id": 7, "body": "Agreed — merging now" }
```
Success `201 Created`:
```json
{
  "message": "Comment created",
  "comment": { "...": "comment object (see §3)" }
}
```
Errors: `400` (missing/invalid field, non-existent task or parent comment), `401`.

---

#### `POST /api/project/add`
Create a project. Auth: **Bearer**. `created_by_id` is taken from the token.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `name` | string | **yes** | 1–120 characters (trimmed). Unique (case-insensitive) → duplicate yields `400`. |
| `description` | string | no | Up to 4000 chars; blank/omitted → `null`. |

Request:
```json
{ "name": "Apollo", "description": "Rocket programme" }
```
Success `201 Created`:
```json
{ "project": { "...": "project object (see §3)" } }
```
Errors: `400` (missing/invalid field, duplicate name), `401`.

---

#### `GET /api/project/all`
List all projects (for project pickers), alphabetical by name. Auth: **Bearer**. Always includes the built-in "Unidentified" project.

Success `200 OK`:
```json
{ "projects": [ { "...": "project object" } ] }
```
Errors: `401`.

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

### Blockers (real-time)

#### `POST /api/task/block`
Flag a task as blocked on another member and alert them. Auth: **Bearer**. Callable by the task's creator or any of its assignees.

In one transaction this sets the task's `status` to `blocked`, bumps its `version`, records a `blocked` task event, and stores a `blocker` notification for the named member. It is then pushed to that member's open WebSocket connections (see §6); if they have none, the stored notification is what they are shown on their next connect.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `responsible_user_id` | integer | **yes** | Must be an existing active user, and **not** the caller, else `400`. |
| `message` | string | **yes** | 1–4000 characters (trimmed); blank → `400`. |

Request:
```json
{ "task_id": 12, "responsible_user_id": 4, "message": "Waiting on the revised wiring diagram." }
```
Success `201 Created`:
```json
{
  "message": "Blocker raised",
  "task": { "...": "task object, status now \"blocked\", version incremented" },
  "notification": { "...": "notification object, notification_type \"blocker\"" }
}
```
Errors: `400` (bad field, unknown task/member, naming yourself), `401`, `403` (not the creator or an assignee).

---

#### `GET /api/notification/pending-blockers`
Blocker alerts raised against the caller that they have not acknowledged, oldest first. Auth: **Bearer**. The client fetches this on connect so an alert raised while they were offline is still shown.

Success `200 OK`:
```json
{ "notifications": [ { "...": "notification object with read_at: null" } ] }
```
Errors: `401`.

---

#### `POST /api/notification/ack`
Acknowledge one of the caller's own notifications by stamping its `read_at`, so it stops being replayed. Auth: **Bearer**.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `notification_id` | integer | **yes** | Must be an existing notification **owned by the caller**, else `400`. |

Acknowledging twice is not an error; the original timestamp is kept. A notification belonging to someone else reports the same "not found" as one that does not exist, so ids cannot be probed.

Success `200 OK`:
```json
{ "message": "Notification acknowledged", "notification_id": 5 }
```
Errors: `400` (unknown id, or not yours), `401`.

---

### Editing and deleting

These five endpoints share one permission model. A `403 Forbidden` means the
token is valid but the user is not allowed to touch that record:

| Record | Who may edit | Who may delete |
| --- | --- | --- |
| task | its creator **or** any of its assignees | its creator only |
| note | its author only | its author only |
| comment | its author only | its author only |

---

#### `POST /api/task/update`
Edit an existing task. Auth: **Bearer**. Bumps `version`, refreshes `updated_at`, and records an `updated` event.

This is a **partial** update: only the keys present in the body change. An
omitted key leaves the column as-is; an explicit `null` clears a nullable
column. (`"description": null` erases the description, while omitting
`description` keeps it.)

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |
| `title` | string | no | 1–200 characters (trimmed). Cannot be set to empty. |
| `description` | string \| null | no | Up to 4000 chars; `null` or blank clears it. |
| `status` | string | no | One of the five statuses. |
| `type` | string | no | One of the `type` enum values (see §3). |
| `discipline` | string | no | One of the `discipline` enum values (see §3). |
| `due_at` | string \| null | no | Timestamp string; `null` clears it. |
| `start_at` | string \| null | no | Timestamp string; `null` clears it. |
| `assignee_ids` | array of integers \| null | no | **Replaces** the whole assignee set. `[]` or `null` unassigns everyone. Each id must be an existing active user, else `400`. |
| `project_id` | integer | no | Must be an existing project id, else `400`. Cannot be null — every task belongs to a project. |

At least one field besides `task_id` must be present, else `400`.

Request (rename and reassign, leaving everything else alone):
```json
{ "task_id": 12, "title": "Write Q4 report (final)", "assignee_ids": [1, 4] }
```
Request (clear the due date):
```json
{ "task_id": 12, "due_at": null }
```
Success `200 OK`:
```json
{ "task": { "...": "task object (with incremented version)" } }
```
Errors: `400` (no fields, bad value, non-existent task/assignee/project), `401`, `403` (not the creator or an assignee).

---

#### `POST /api/task/delete`
Delete a task. Auth: **Bearer**. Also removes its notes, comments (and their nested replies), events, assignee rows and notifications.

**Refuses while the task still has subtasks** — delete those first. This is deliberate: it avoids silently destroying a tree of work.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `task_id` | integer | **yes** | Must be an existing task id, else `400`. |

Request:
```json
{ "task_id": 12 }
```
Success `200 OK`:
```json
{ "message": "Task deleted", "deleted_task_id": 12 }
```
Errors: `400` (non-existent task, or it still has subtasks — the message says how many), `401`, `403` (not the creator).

---

#### `POST /api/task/note/update`
Edit a note's body. Auth: **Bearer**. Author only. Refreshes the note's `updated_at`.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `note_id` | integer | **yes** | Must be an existing note id, else `400`. |
| `body` | string | **yes** | 1–4000 characters (trimmed); blank → `400`. |

Request:
```json
{ "note_id": 7, "body": "Draft sent for review (v2)" }
```
Success `200 OK`:
```json
{ "message": "Note updated", "note": { "...": "note object" } }
```
Errors: `400`, `401`, `403` (not the author).

---

#### `POST /api/task/note/delete`
Delete a note. Auth: **Bearer**. Author only.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `note_id` | integer | **yes** | Must be an existing note id, else `400`. |

Success `200 OK`:
```json
{ "message": "Note deleted", "deleted_note_id": 7 }
```
Errors: `400`, `401`, `403` (not the author).

---

#### `POST /api/task/comment/update`
Edit a comment's body. Auth: **Bearer**. Author only. Refreshes `updated_at`; posts no new notifications.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `comment_id` | integer | **yes** | Must be an existing comment id, else `400`. |
| `body` | string | **yes** | 1–4000 characters (trimmed); blank → `400`. |

Success `200 OK`:
```json
{ "message": "Comment updated", "comment": { "...": "comment object" } }
```
Errors: `400`, `401`, `403` (not the author).

---

#### `POST /api/task/comment/delete`
Delete a comment. Auth: **Bearer**. Author only.

**Nested replies cascade** — deleting a comment removes the whole thread beneath it, including replies written by other people. `deleted_reply_count` reports how many went with it.

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `comment_id` | integer | **yes** | Must be an existing comment id, else `400`. |

Success `200 OK`:
```json
{ "message": "Comment deleted", "deleted_comment_id": 5, "deleted_reply_count": 2 }
```
Errors: `400`, `401`, `403` (not the author).

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
List every task, newest first. Auth: **Bearer**.

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
  "notes": [ { "...": "note object (see §3)" } ],
  "comments": [ { "...": "comment object (see §3)" } ]
}
```
`subtasks` are **direct children only** (one level, not recursive), oldest first; `notes` and `comments` are oldest first. All are `[]` when there are none. `comments` is a flat list ordered oldest-first; nesting is reconstructed client-side from each comment's `parent_comment_id`.
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
| POST | `/api/auth/login` | — | `login`, `password` → returns `refresh_token` in body |
| POST | `/api/auth/refresh` | — | `refresh_token` → rotates it, returns the new one in body |
| POST | `/api/auth/logout` | Bearer | _(none)_ → client discards its stored refresh token |
| GET | `/api/auth/me` | Bearer | — |
| POST | `/api/task/add` | Bearer | `title`(+ optional `description`, `status`, `due_at`, `assignee_ids`, `parent_task_id`, `project_id`) |
| POST | `/api/task/subtask` | Bearer | `parent_task_id`, `title`(+ optional `description`, `status`, `due_at`, `assignee_ids`, `project_id`) |
| POST | `/api/task/note` | Bearer | `task_id`, `body` |
| POST | `/api/task/comment` | Bearer | `task_id`, `body`(+ optional `parent_comment_id`) → notifies assignees + parent-comment author |
| POST | `/api/task/status` | Bearer | `task_id`, `status` |
| POST | `/api/task/block` | Bearer | `task_id`, `responsible_user_id`, `message` → sets status `blocked`, alerts them live |
| GET | `/api/notification/pending-blockers` | Bearer | — → unacknowledged blocker alerts for the caller |
| POST | `/api/notification/ack` | Bearer | `notification_id` → stops it being replayed |
| WS | `/ws/notifications` | first-message auth | see §6 |
| POST | `/api/task/update` | Bearer | `task_id` + any editable field (partial; `null` clears) → creator or assignee |
| POST | `/api/task/delete` | Bearer | `task_id` → creator only; refuses while subtasks remain |
| POST | `/api/task/note/update` | Bearer | `note_id`, `body` → author only |
| POST | `/api/task/note/delete` | Bearer | `note_id` → author only |
| POST | `/api/task/comment/update` | Bearer | `comment_id`, `body` → author only |
| POST | `/api/task/comment/delete` | Bearer | `comment_id` → author only; replies cascade |
| GET | `/api/task/all` | Bearer | — |
| GET | `/api/task/mine` | Bearer | — |
| GET | `/api/task/completed` | Bearer | — |
| GET | `/api/task/detail` | Bearer | query `task_id` → `{ task, subtasks, notes, comments }` |
| POST | `/api/project/add` | Bearer | `name`(+ optional `description`) |
| GET | `/api/project/all` | Bearer | — |
| GET | `/api/user/all` | Bearer | — |
| GET | `/api/notification/all` | Bearer | — |

## 6. WebSocket — live blocker alerts

| Context | URL |
| --- | --- |
| Production (nginx, same origin) | `wss://<host>/ws/notifications` |
| Direct local dev | `wss://<host>:5555/ws/notifications` |

The scheme follows the page: `https` → `wss`, `http` → `ws`.

**Authentication is by first message, not by header or query string.** A browser
cannot set `Authorization` on a WebSocket handshake, and a token in the query
string would be written into nginx and Drogon access logs — which
`backend/README.md` forbids. So the socket opens unauthenticated and the client
immediately sends:

```json
{ "type": "auth", "access_token": "<jwt>" }
```

The server replies `{"type":"auth_ok","user_id":3}`, or sends
`{"type":"error","error":"..."}` and closes with code `1008`. A socket that has
not authenticated within **10 seconds** is closed. The connection's `Origin` is
checked against `TASK_MANAGER_CORS_ORIGIN` at handshake time, because CORS does
not apply to WebSockets.

After authenticating, the client may send `{"type":"ping"}` and gets
`{"type":"pong"}` — used to keep idle proxies from reaping the connection
(nginx's default read timeout is 60s; the client pings every 30s).

**Server → client**, when a blocker names this user:

```json
{
  "type": "blocker",
  "notification": { "...": "notification object" },
  "task": { "...": "task object" }
}
```

Delivery is best-effort and goes to **every** open tab for that user. A user
with no live socket gets nothing pushed — the stored notification row is the
guarantee, replayed via `GET /api/notification/pending-blockers` on the next
connect. The client shows each alert as a modal that cannot be dismissed except
by its OK button, which then calls `POST /api/notification/ack`.

**Deployment note:** nginx does not proxy WebSockets without being told to. The
`/ws/` location needs:

```nginx
location /ws/ {
    proxy_pass https://127.0.0.1:5555;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

Without `Upgrade`/`Connection`, the handshake fails and the client falls back to
reconnect attempts forever.

Socket state is **per backend process** (an in-memory map of user id →
connections), the same single-process assumption the SQLite setup and the IP
rate limiter already make. Two backend processes would each only reach their own
clients.

## 7. Not yet implemented (planned)

- Reading the task event history. `task_events` is **written** by
  `POST /api/task/subtask`, `POST /api/task/status` and `POST /api/task/update`,
  but there is no endpoint to read it. (A task's notes, comments and direct
  subtasks are readable via `GET /api/task/detail`.)
- Optimistic concurrency on edit and status change. `version` is returned and
  incremented, but no endpoint accepts a client-supplied expected `version`, so
  two concurrent edits silently last-write-wins.
- Marking **non-blocker** notifications read. `POST /api/notification/ack` works on any of the caller's notifications, but only the blocker modal calls it; the bell still filters what it has shown in memory for the session, so a comment notification reappears after a reload.
- Clearing a blocker. A task can be flagged `blocked` via `POST /api/task/block`, but the only way back out is a plain `POST /api/task/status` — which records a `status_changed` event, not the `unblocked` one the schema allows, and does not notify the member who raised it.
- Notifications on edit/delete. Reassigning a task via `POST /api/task/update`
  does not notify the new assignees, and deleting a task or comment notifies
  nobody.
- Deleting a task that still has subtasks (deliberately refused — see
  `POST /api/task/delete`). There is no cascade option and no "move subtasks to
  another parent" endpoint.
- Editing or deleting a project.
