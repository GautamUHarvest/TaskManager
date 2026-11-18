UPDATE users
SET email_verified_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE is_active = 1 AND email_verified_at IS NULL;
