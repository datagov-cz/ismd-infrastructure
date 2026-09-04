# restart-count

**Trigger**: `RestartCount` total > 3 in 15 min on a Container App. Sev2 quiet.

**What it means**: replicas are restarting more than a normal deploy rollover would explain. Likely a crashloop or aggressive probe failures.

**First look**:
1. Container App System logs around the alert window: `ContainerStarted` / `ContainerCreated` / `Killing` events.
2. Console logs around each restart — startup error? Liveness probe timeout?
3. Revision management: latest revision active and serving 100% traffic, or rolling between two?

**Common causes**:
- Crashloop on startup (config error, missing env var, dependency unreachable).
- Liveness/readiness probe too aggressive (timeout too low, path returns slow).
- Recent deploy that broke startup — roll back via `az containerapp revision activate --revision <previous>`.

**Resolution**: fix root cause and redeploy, or roll back to last known good revision.
