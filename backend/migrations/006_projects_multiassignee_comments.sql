-- 006: Projects, multi-assignee tasks, and threaded comments with notifications.
--
-- Note: migrations run inside a transaction (BEGIN IMMEDIATE ... COMMIT), and
-- `PRAGMA foreign_keys` is a no-op inside a transaction, so FK enforcement is
-- whatever the connection opened with (ON). The seed below therefore relies on
-- created_by_id being nullable rather than on toggling FK enforcement.

-- 1. Projects table. Every task belongs to a project.
--    created_by_id is nullable: the built-in default project has no human
--    creator (a NULL foreign key passes the FK check). User-created projects
--    always carry the id of the authenticated creator.
CREATE TABLE projects (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL COLLATE NOCASE,
    description TEXT,
    created_by_id INTEGER,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (length(trim(name)) > 0),
    FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX projects_name_unique_idx ON projects(name COLLATE NOCASE);

-- Seed the default project with a NULL creator (system-owned, no user row).
INSERT INTO projects (id, name, description, created_by_id)
VALUES (1, 'Unidentified', 'Default project for tasks not yet assigned to a project', NULL);

-- 2. Add project_id to tasks, defaulting existing rows to the "Unidentified"
--    project (id = 1).
--
--    SQLite forbids ADD COLUMN with a REFERENCES clause unless the default is
--    NULL, so we cannot attach a table-level foreign key here (and ALTER TABLE
--    cannot add a constraint to an existing table without a full rebuild).
--    project_id existence is therefore enforced in the service layer
--    (TaskService validates the project exists before inserting a task); the
--    NOT NULL DEFAULT 1 keeps every row pointing at a real project, and no
--    endpoint deletes projects, so a task can never be orphaned.
ALTER TABLE tasks ADD COLUMN project_id INTEGER NOT NULL DEFAULT 1;

CREATE INDEX tasks_project_id_idx ON tasks(project_id);

-- 3. Multi-assignee: junction table. The old assignee_id column stays for now
--    (read-only / ignored by new code) so we don't break in-flight data.
CREATE TABLE task_assignees (
    task_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    assigned_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (task_id, user_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- Migrate existing single-assignee data into the junction table.
INSERT INTO task_assignees (task_id, user_id)
SELECT id, assignee_id FROM tasks WHERE assignee_id IS NOT NULL;

-- 4. Threaded comments. parent_comment_id enables nested replies.
CREATE TABLE comments (
    id INTEGER PRIMARY KEY,
    task_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    parent_comment_id INTEGER,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (length(trim(body)) > 0),
    CHECK (parent_comment_id IS NULL OR parent_comment_id != id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (parent_comment_id) REFERENCES comments(id) ON DELETE CASCADE
);

CREATE INDEX comments_task_created_idx ON comments(task_id, created_at);
CREATE INDEX comments_parent_idx ON comments(parent_comment_id);
