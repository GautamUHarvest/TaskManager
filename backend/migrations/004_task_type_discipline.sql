-- Add type, discipline, and start_at columns to tasks.
-- type and discipline default to 'decide' (meaning "to be decided").

ALTER TABLE tasks ADD COLUMN type TEXT NOT NULL DEFAULT 'decide'
    CHECK (type IN (
        'design', 'test', 'decide', 'measure', 'select', 'buy',
        'admin', 'code', 'make', 'data', 'doc', 'integrate'
    ));

ALTER TABLE tasks ADD COLUMN discipline TEXT NOT NULL DEFAULT 'decide'
    CHECK (discipline IN (
        'mechanical', 'electronics', 'software', 'server_backend',
        'communications', 'embedded', 'control_systems',
        'project_management', 'operations', 'payments',
        'systems_integration', 'frontend', 'decide'
    ));

ALTER TABLE tasks ADD COLUMN start_at TEXT DEFAULT NULL;
