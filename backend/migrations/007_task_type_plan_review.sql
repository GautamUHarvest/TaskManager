-- 007: Add 'plan' and 'review' to the allowed task types.
--
-- SQLite cannot alter an existing CHECK constraint, and rebuilding `tasks`
-- would mean dropping a table that half the schema references by foreign key.
-- Instead swap the column: add a replacement with the wider CHECK, copy the
-- values, drop the old column (allowed because its CHECK is a column
-- constraint and it is not indexed, keyed, or used by a trigger/view), and
-- rename the replacement into place. Requires SQLite >= 3.35 (DROP COLUMN).
--
-- The column moves to the end of the table; every query names its columns, so
-- position does not matter.
--
-- Keep this list in sync with kTaskTypes in services/TaskRules.cc.

ALTER TABLE tasks ADD COLUMN type_v2 TEXT NOT NULL DEFAULT 'decide'
    CHECK (type_v2 IN (
        'design', 'test', 'decide', 'measure', 'select', 'buy',
        'admin', 'code', 'make', 'data', 'doc', 'integrate',
        'plan', 'review'
    ));

UPDATE tasks SET type_v2 = type;

ALTER TABLE tasks DROP COLUMN type;

ALTER TABLE tasks RENAME COLUMN type_v2 TO type;
