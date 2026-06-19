# postgres-memory-high

**Trigger**: `memory_percent` > 85% average over 15 min. Sev3 quiet.

**First look**:
1. Connection count: `SELECT count(*) FROM pg_stat_activity;` — bloated?
2. Recent query workload — sorts/hashes spilling?
3. Server parameters — `work_mem`, `shared_buffers` reasonable for SKU?

**Common causes**: too many app connections (no pooling), huge sort operations, undersized SKU for current load.

**Resolution**: enable PgBouncer pooling on the app side, tune `work_mem`, or scale SKU.
