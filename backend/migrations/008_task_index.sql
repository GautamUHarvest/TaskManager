-- 008: A per-project display index ("#" in the planning sheet).
--
-- `task_index` is the task's position within its project: lists are ordered
-- by it, and new tasks are appended with MAX + 1 (TaskRepository). It is
-- deliberately NOT unique — renumbering a list means swapping values between
-- rows, which a unique constraint would reject mid-way; ties fall back to id.
--
-- Nullable only because ADD COLUMN cannot backfill a NOT NULL column from an
-- expression; the backfill below fills every existing row and the repository
-- always writes a value.

ALTER TABLE tasks ADD COLUMN task_index INTEGER
    CHECK (task_index IS NULL OR task_index > 0);

-- Existing tasks: number them 1..N per project in creation order.
UPDATE tasks
SET task_index = (
    SELECT numbered.position
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY project_id ORDER BY created_at, id
               ) AS position
        FROM tasks
    ) AS numbered
    WHERE numbered.id = tasks.id
);

CREATE INDEX tasks_project_index_idx ON tasks(project_id, task_index);
