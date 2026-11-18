ALTER TABLE users ADD COLUMN email TEXT COLLATE NOCASE;
ALTER TABLE users ADD COLUMN email_verified_at TEXT;

CREATE UNIQUE INDEX users_email_unique_idx
    ON users(email COLLATE NOCASE)
    WHERE email IS NOT NULL;

CREATE TRIGGER users_email_domain_insert
BEFORE INSERT ON users
WHEN NEW.email IS NOT NULL
     AND lower(substr(NEW.email, -12)) != '@uharvest.in'
BEGIN
    SELECT RAISE(ABORT, 'email must use the @uharvest.in domain');
END;

CREATE TRIGGER users_email_domain_update
BEFORE UPDATE OF email ON users
WHEN NEW.email IS NOT NULL
     AND lower(substr(NEW.email, -12)) != '@uharvest.in'
BEGIN
    SELECT RAISE(ABORT, 'email must use the @uharvest.in domain');
END;

CREATE TABLE email_verification_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    consumed_at INTEGER,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX email_verification_tokens_user_idx
    ON email_verification_tokens(user_id, expires_at);

CREATE TABLE auth_sessions (
    id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    refresh_token_hash TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX auth_sessions_user_idx ON auth_sessions(user_id, expires_at);
