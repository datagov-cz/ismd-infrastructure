# http-5xx

**Trigger**: `Requests` metric where `statusCodeCategory = 5xx` > 0 in a 5-min window on a Container App. Sev2 quiet.

**What it means**: at least one request returned 5xx. Could be a one-off scaling blip or a real app error.

**First look**:
1. Per-app Logs blade → recent ERROR/exception entries around the alert timestamp.
2. If empty: AppGW access logs in `ismdmonglobal/insights-logs-applicationgatewayaccesslog/` for the exact failing request (URL, backend, response time).
3. Container App System logs around the same time — was there a scale-up event? (cold-start blip is the most common false positive)

**Common causes**:
- **Scale-up cold-start**: traffic burst triggers a new replica; ingress briefly routes to not-yet-ready replica → 5xx. Look for `SuccessfulRescale` in system logs ±2 min.
- **Real app error**: stack trace in console logs. Fix in code.
- **Upstream dependency down** (Postgres, Fuseki, Keycloak) — check the companion alerts on those resources.
- **Network policy / NSG**: rare in DEV; possible after subnet changes.

**Resolution**:
- Scale-up blip: expected below the threshold. Non-prod fires at >3 5xx / 5m (dev/test scale-to-zero produces routine 1-2 cold-start 5xx that are not incidents); prod fires at >0. A single blip should no longer page.
- App error: fix and redeploy.
- Upstream: resolve at the upstream first.
