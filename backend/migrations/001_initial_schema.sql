PRAGMA foreign_keys = ON;

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL COLLATE NOCASE UNIQUE,
    employee_id TEXT NOT NULL COLLATE NOCASE UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (length(trim(username)) > 0),
    CHECK (length(trim(employee_id)) > 0),
    CHECK (length(trim(display_name)) > 0)
);

CREATE TABLE tasks (
    id INTEGER PRIMARY KEY,
    parent_task_id INTEGER,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'todo'
        CHECK (status IN ('todo', 'in_progress', 'blocked', 'done', 'cancelled')),
    due_at TEXT,
    assignee_id INTEGER,
    created_by_id INTEGER NOT NULL, 
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (length(trim(title)) > 0),
    CHECK (parent_task_id IS NULL OR parent_task_id != id),
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id) ON DELETE RESTRICT,
    FOREIGN KEY (assignee_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE task_notes (
    id INTEGER PRIMARY KEY,
    task_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (length(trim(body)) > 0),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE RESTRICT,
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE task_events (
    id INTEGER PRIMARY KEY,
    task_id INTEGER NOT NULL,
    actor_id INTEGER NOT NULL,
    event_type TEXT NOT NULL CHECK (
        event_type IN (
            'created',
            'updated',
            'assigned',
            'due_date_changed',
            'status_changed',
            'blocked',
            'unblocked',
            'subtask_created'
        )
    ),
    details TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE RESTRICT,
    FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE notifications (
    id INTEGER PRIMARY KEY,
    recipient_id INTEGER NOT NULL,
    actor_id INTEGER NOT NULL,
    task_id INTEGER NOT NULL,
    notification_type TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    read_at TEXT,
    CHECK (length(trim(notification_type)) > 0),
    CHECK (length(trim(message)) > 0),
    FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE RESTRICT
);

CREATE INDEX tasks_parent_task_id_idx ON tasks(parent_task_id);
CREATE INDEX tasks_assignee_status_due_idx ON tasks(assignee_id, status, due_at);
CREATE INDEX task_notes_task_created_idx ON task_notes(task_id, created_at);
CREATE INDEX task_events_task_created_idx ON task_events(task_id, created_at);
CREATE INDEX notifications_recipient_unread_idx
    ON notifications(recipient_id, created_at)
    WHERE read_at IS NULL;
