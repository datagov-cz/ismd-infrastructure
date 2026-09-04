# postgres-db-alive

**Trigger**: `is_db_alive` < 1 for 5 min on `ismd-tool-postgres-<env>`. Sev1 paging.

**What it means**: tool DB is unreachable. Tool app is down.

**First look**:
1. Portal → Postgres Flexible Server → Overview. Status?
2. Server logs (portal blade).
3. Recent activity log (auto-restart? failover?).

**Common causes**:
- Azure-side maintenance window or restart — wait for completion.
- Disk exhausted — check `postgres-storage-high` companion alert; usually fires first.
- Network change (subnet, private endpoint) — recent terraform apply?
- Real backend outage in the region.

**Resolution**: restart via portal if not in middle of recovery; open Azure support if extended.
