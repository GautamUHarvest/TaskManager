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
- **Access token lifetime:** 10 minutes (`expires_in` = `600`). Use `POST /api/auth/refresh` to get a new one; the refresh token rotates on every use.
- **Token storage (client):** keep tokens in memory only (they are cleared on reload). Do not put them in URLs or logs.
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
Rotate the refresh token and get a new access token. Auth: **none** (the refresh token is the credential).

| Field | Type | Required |
| --- | --- | --- |
| `refresh_token` | string | yes |

Request:
```json
{ "refresh_token": "<opaque>" }
```
Success `200 OK`: a **tokens** object (with a **new** `refresh_token` — replace the stored one).
Errors: `401` (invalid/expired/already-rotated), `400`.

---

#### `POST /api/auth/logout`
Revoke the current session. Auth: **Bearer**. **No request body.**

Success `204 No Content` (empty body).
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
| POST | `/api/auth/login` | — | `login`, `password` |
| POST | `/api/auth/refresh` | — | `refresh_token` |
| POST | `/api/auth/logout` | Bearer | _(none)_ |
| GET | `/api/auth/me` | Bearer | — |
| POST | `/api/task/add` | Bearer | `title`(+ optional `description`, `status`, `due_at`, `assignee_ids`, `parent_task_id`, `project_id`) |
| POST | `/api/task/subtask` | Bearer | `parent_task_id`, `title`(+ optional `description`, `status`, `due_at`, `assignee_ids`, `project_id`) |
| POST | `/api/task/note` | Bearer | `task_id`, `body` |
| POST | `/api/task/comment` | Bearer | `task_id`, `body`(+ optional `parent_comment_id`) → notifies assignees + parent-comment author |
| POST | `/api/task/status` | Bearer | `task_id`, `status` |
| GET | `/api/task/all` | Bearer | — |
| GET | `/api/task/mine` | Bearer | — |
| GET | `/api/task/completed` | Bearer | — |
| GET | `/api/task/detail` | Bearer | query `task_id` → `{ task, subtasks, notes, comments }` |
| POST | `/api/project/add` | Bearer | `name`(+ optional `description`) |
| GET | `/api/project/all` | Bearer | — |
| GET | `/api/user/all` | Bearer | — |
| GET | `/api/notification/all` | Bearer | — |

## 6. Not yet implemented (planned)

- Update/delete task, assign/reassign, due-date changes.
- Reading the task event history. `task_events` is **written** by
  `POST /api/task/subtask` and `POST /api/task/status`, but there is no endpoint
  to read it. (A task's notes and direct subtasks are now readable via
  `GET /api/task/detail`.)
- Optimistic concurrency on status change (no client-supplied expected `version`).
- Marking notifications read (they are now **written** on `POST /api/task/comment` — to each assignee and, on a reply, the parent comment's author, excluding the comment's own author — and on no other action yet, but there is still no mark-as-read endpoint).
- Reassigning a task's assignees or moving it between projects after creation (assignees and `project_id` are set at creation only).
