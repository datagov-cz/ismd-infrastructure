# postgres-cpu-high

**Trigger**: `cpu_percent` > 80% average over 15 min. Sev3 quiet.

**First look**:
1. Portal → Postgres → Server parameters → confirm SKU still appropriate.
2. Connect with psql: `SELECT * FROM pg_stat_activity WHERE state = 'active';` — long-running queries?
3. `pg_stat_statements` (if enabled) → top by total_time.

**Common causes**: missing index causing seq scans; runaway analytics query; connection pool maxed; misconfigured app issuing per-row queries.

**Resolution**: kill bad query, add index, optimize app, or scale SKU.
