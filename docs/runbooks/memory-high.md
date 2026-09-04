# memory-high

**Trigger**: `WorkingSetBytes` > ~1.7 GiB average over 15 min. Sev3 quiet.

**What it means**: app is using a lot of memory. Risk of OOM kill if it keeps climbing.

**First look**:
1. Container App metrics → WorkingSetBytes graph. Climbing steadily = leak; flat-high = expected.
2. App Insights `exceptions` table for OOM-related exceptions (`OutOfMemoryError` in Java apps).
3. Container App System logs for `Killing` / `OOMKilled` events.

**Common causes**:
- Memory leak (caches not bounded, listeners not detached) — find via heap dump.
- Undersized container limit — bump in terraform module.
- Legitimate working set (Fuseki dataset cache is normal at ~1.7 GiB post-bump).

**Resolution**: fix leak, raise memory limit, or shut down idle apps.
