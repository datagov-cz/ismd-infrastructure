# replicas-zero

**Trigger**: `Replicas` metric ≤ 0 for ≥ 5 min on a Container App. Sev1.

**What it means**: the app has no running replicas. Users hitting that endpoint via AppGW get 404/502.

**First look**:
1. Azure Portal → Container Apps → `<app-name>` → Revision management. Is the latest revision "Active" with replicas?
2. Container App → Logs (per-app blade, NOT the CAE Logs blade) — look for the most recent startup or crash.
3. Container App → System logs (azurerm_monitor table `ContainerAppSystemLogs_CL`) for image pull failures, OOM kills, readiness probe failures.

**Common causes**:
- **Image pull failure** (GHCR PAT expired or tag deleted) — confirm via the `ghcr-pull-failure` companion alert; rotate PAT, redeploy.
- **Crashloop** (app exits on startup) — fix code, redeploy.
- **min_replicas accidentally set to 0** — check `azurerm_container_app.<name>.template.min_replicas` in terraform.
- **CAE-level outage** — rare; check the CAE in Azure portal.

**Resolution**: usually a redeploy from `latest` tag or a code fix. If urgent, manually scale up via `az containerapp update --min-replicas 1`.
