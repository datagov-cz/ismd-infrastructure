# postgres-connection-failures

**Trigger**: `connections_failed` > 5 total over 5 min. Sev2 quiet.

**What it means**: clients are being refused. Authentication, pool exhaustion, or network.

**First look**:
1. Container App logs for the consuming app — auth/connection errors?
2. Postgres logs (portal blade) — `FATAL: password authentication failed` / `too many clients`?
3. Recent terraform apply that touched the password or firewall?

**Common causes**:
- App pool exhausted (max_connections hit).
- Password rotation didn't propagate to the app's env var.
- Firewall rule changed; client IP not allowed.

**Resolution**: align app's credential, raise `max_connections`, or fix firewall.
