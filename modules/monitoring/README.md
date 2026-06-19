# Monitoring Module

Per-env module that wires Azure Monitor alert routing to Teams + email.

## What it creates

- **Action Groups** that route alerts:
  - `ag-dia-quiet-{env}` — Teams post via webhook, no email
  - `ag-dia-paging-{env}` — Teams post via webhook + email to recipients list (only created when `paging_email_recipients` is non-empty; primarily PROD)
- **Logic App** that receives Azure Monitor common alert schema JSON and posts an Adaptive Card to the configured Teams channel
- **API Connection** to the Office 365 / Teams connector (needs one-time OAuth authorization in the portal after first apply)
- Alert rules (per-resource, parameterized over the resources passed in by the env caller)

## Inputs

See `variables.tf`. Required at minimum:
- `environment` (dev/test/prod)
- `resource_group_name`, `location`
- `log_analytics_workspace_id`, `application_insights_id`

Optional:
- `paging_email_recipients` — list of emails; empty list → no paging action group
- `teams_channel_id`, `teams_group_id` — required once Logic App connector is authorized

## Policy

**All monitoring config lives in terraform. No portal clickops.**
The only manual step is the one-time OAuth authorization of the Teams connector in `azurerm_api_connection.teams` after first apply — Microsoft API requires a user identity to grant the connector consent, terraform cannot do this. Document the date + identity + connection ID in the runbook.

## Phase rollout

This module is built up in phases:
- Phase 1a (this commit): Action Groups + module skeleton, webhook URLs as variables
- Phase 1b: Logic App + Teams connector + 1 canary alert end-to-end
- Phase 2: Container App alert set (5xx, replicas, restart count, latency)
- Phase 3: AppGW + Keycloak + Fuseki alerts
- Phase 4: Diagnostic settings matrix (incl. CAE-level → populates CAE Logs blade)
- Phase 5: Application Insights availability tests
