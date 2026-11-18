-- Backfill existing tasks with NULL type/discipline to 'decide'.
UPDATE tasks SET type = 'decide' WHERE type IS NULL;
UPDATE tasks SET discipline = 'decide' WHERE discipline IS NULL;
