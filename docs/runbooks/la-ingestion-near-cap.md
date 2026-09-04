# la-ingestion-near-cap

**Trigger**: LA workspace daily ingestion ≥ 80% of `daily_quota_gb` (currently 0.5 GB/day). Sev2 quiet (or Sev1 paging in PROD).

**Why this matters**: at 100% Azure SILENTLY stops ingestion until UTC midnight. Log-based alerts cannot fire on data that isn't there → you lose visibility during the exact incident generating extra logs. Fix BEFORE the cap trips.

**First look**:
1. Portal → Log Analytics Workspace → Usage and estimated costs.
2. Top ingesting tables:
   ```kql
   Usage
   | where TimeGenerated > ago(24h)
   | where IsBillable
   | summarize TotalGB = sum(Quantity)/1024 by DataType
   | order by TotalGB desc
   ```
3. Source: who's writing too much? Check resource diagnostic settings; recent app change emitting verbose logs?

**Resolution**:
- Quick fix: raise `log_analytics_daily_cap_gb` in `modules/shared` (per-env tfvar if set).
- Better fix: identify the noisy source and reduce log verbosity at the source.
