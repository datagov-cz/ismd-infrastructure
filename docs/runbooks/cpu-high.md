# cpu-high

**Trigger**: `UsageNanoCores` > 800 000 000 (~0.8 vCPU equivalent) average over 15 min. Sev3 quiet.

**What it means**: app is hot. Not an outage; might be a real load increase or a runaway loop.

**First look**:
1. App Insights `requests` table — request volume up?
2. Container App Logs — repeated work / hot loop / busy GC?
3. Per-app metrics blade → CPU graph last 24h. New baseline or transient spike?

**Common causes**:
- Real traffic increase — fine, no action; revisit if sustained for hours.
- Inefficient code path (N+1 query, recursion, slow GC) — profile.
- Background job stuck in a retry loop — check app logs.

**Resolution**: profile and fix, or scale out (raise max replicas / right-size SKU).
