# Alert Runbooks

One short runbook per alert rule. Each describes: **what the alert means**, **where to look first**, **common causes**, and **how to resolve**. Optimized for "fix tomorrow morning" — none of these are on-call pages today.

## ⚠️ Status: v1 drafts — validate on first real use

These were written speculatively when the alert rules were created. The KQL queries, CLI commands, and the AppGW backend-health command have been spot-checked against DEV, but **portal navigation paths, suggested resolution steps, and the more specific advice in each runbook have NOT been walked through end-to-end**. Treat them as starting points, not authoritative procedures.

When you actually use a runbook to resolve an incident:
- Note anything that's wrong, outdated, or missing.
- Edit the runbook in the same PR as the incident fix (or in a follow-up).
- Update this README's status section if a whole batch has been validated.

Known correction already applied:
- `ghcr-pull-failure.md` — initially referenced a `registry_password` Container App secret that doesn't exist (our GHCR images are public; no PAT is configured). Updated.

## Convention

- File name matches the alert rule pattern: `al-dia-<slug>.md` (env suffix stripped).
- Alert `description` field in terraform references the runbook by relative path:
  `… See: docs/runbooks/al-dia-<slug>.md`
- The runbook stays short (~10 lines). Long writeups belong in `docs/` proper.

## Index

| Alert rule | Runbook |
|---|---|
| `al-dia-{app}-replicas-zero-{env}` | [replicas-zero.md](replicas-zero.md) |
| `al-dia-{app}-5xx-{env}` | [http-5xx.md](http-5xx.md) |
| `al-dia-{app}-cpu-high-{env}` | [cpu-high.md](cpu-high.md) |
| `al-dia-{app}-memory-high-{env}` | [memory-high.md](memory-high.md) |
| `al-dia-{app}-restart-count-{env}` | [restart-count.md](restart-count.md) |
| `al-dia-tool-postgres-db-alive-{env}` | [postgres-db-alive.md](postgres-db-alive.md) |
| `al-dia-tool-postgres-cpu-high-{env}` | [postgres-cpu-high.md](postgres-cpu-high.md) |
| `al-dia-tool-postgres-memory-high-{env}` | [postgres-memory-high.md](postgres-memory-high.md) |
| `al-dia-tool-postgres-storage-high-{env}` | [postgres-storage-high.md](postgres-storage-high.md) |
| `al-dia-tool-postgres-connection-failures-{env}` | [postgres-connection-failures.md](postgres-connection-failures.md) |
| `al-dia-appgw-backend-unhealthy-{env}` | [appgw-backend-unhealthy.md](appgw-backend-unhealthy.md) |
| `al-dia-appgw-5xx-{env}` | [appgw-5xx.md](appgw-5xx.md) |
| `al-dia-availability-{endpoint}-{env}` | [availability.md](availability.md) |
| `al-dia-la-ingestion-near-cap-{env}` | [la-ingestion-near-cap.md](la-ingestion-near-cap.md) |
| `al-dia-ghcr-pull-failure-{env}` | [ghcr-pull-failure.md](ghcr-pull-failure.md) |
