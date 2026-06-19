# postgres-storage-high

**Trigger**: `storage_percent` > 85% sustained 30 min. Sev2 quiet.

**Why this matters**: at 100% Postgres rejects writes. Once stuck, expanding storage requires a maintenance window. Act at 85%, not 99%.

**First look**:
1. Portal → Postgres → Compute + storage → current size.
2. Top tables by size:
   ```sql
   SELECT schemaname, relname, pg_size_pretty(pg_total_relation_size(relid))
   FROM pg_catalog.pg_statio_user_tables
   ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;
   ```
3. WAL bloat: `SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));`

**Common causes**: unbounded log/audit table, WAL not archived/recycled, autovacuum not keeping up.

**Resolution**: scale storage (portal — irreversible upward); clean up bloat; tune autovacuum.
