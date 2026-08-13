# TODO / Plan — move Postgres out of `tool_apps` into a shared per-env module

**Status:** not started (captured 2026-07-29). Separate from, and not a prerequisite
for, the per-app DB user-separation work (see
`infrastructure/db/user-separation/README.md`). Roles are created *inside* the
database by SQL, independent of which TF module declares the server — do the
security cutover on the current layout regardless of this move.

## Problem

The Postgres Flexible Server is declared in `modules/tool_apps/database.tf`, but it
backs three tenants:

- `ismd_tool_db` + `keycloak_db` — created in `tool_apps`
- `ismd_ai` — created in `ai_apps`, against the server id it's handed
  (`module.tool_apps[0].postgres_server_id`)

That handoff is why `deploy_ai_apps` requires `deploy_tool_apps`. The server is a
shared per-env resource owned by the tool module — a layering violation. Keycloak
and AI both depend on infrastructure that belongs to "tool".

## Target layout

A dedicated per-env module (new `modules/postgres`, or fold into `modules/shared`)
that owns:

- `azurerm_postgresql_flexible_server`
- server-level config: `azure.extensions` (UNACCENT), `idle_session_timeout`,
  `idle_in_transaction_session_timeout`
- firewall rules (`allow_azure`, `app_outbound`, `admin`)
- the admin login variables

Exposes `server_id` / `fqdn` / `name` as outputs.

Then **each app module creates its own database** against the injected `server_id`
— already the `ai_apps` pattern; generalize it so `tool_apps` (tool + keycloak DBs)
does the same instead of owning the server. AI then depends on the postgres module,
not on `tool_apps`, removing the `deploy_ai_apps ⇒ deploy_tool_apps` coupling.

Schema/migrations stay in-app (Liquibase for tool, `schema.sql` for ai) — no change.

## Placement

Per-env `shared`/`postgres`, **not** `shared_global`. Each env has its own server
with its own data; `shared_global` is cross-env (App Gateway, global VNet).

## The hard part — state surgery on a live server with data

Relocating the resource changes its state address, e.g.
`module.dev[0].module.tool_apps[0].azurerm_postgresql_flexible_server.tool[0]`
→ `module.dev[0].module.postgres[0].azurerm_postgresql_flexible_server.tool[0]`.

Must be done with `moved {}` blocks (or `terraform state mv`), never a
destroy/recreate. The plan **must show 0 to destroy** on the server before apply.
Same for every dependent resource that moves with it:

- the 3 server-level `azurerm_postgresql_flexible_server_configuration` resources
- the 3 firewall rules (`allow_azure`, `app_outbound[*]`, `admin[*]`)
- whichever databases move (decide: DBs move into per-app modules referencing the
  injected `server_id`, or stay with the server — pick one and map every address)

Do it on **dev first**, confirm `0 to destroy` in plan, apply, verify apps still
connect. Then test, then prod. Getting an address wrong = destroy/recreate = total
data loss.

## Rough steps

1. Create `modules/postgres` with the server + config + firewall + outputs.
2. Add the module call to each env root; wire `server_id`/`fqdn` into `tool_apps`
   and `ai_apps` (both already accept an injected server id for their DBs — tool
   just needs to stop creating the server).
3. Move DB-creation resources into the owning app modules (tool creates its two,
   ai already creates its one).
4. Write `moved {}` blocks for every relocated address.
5. `./terraw.sh plan` on dev — **verify 0 to destroy**, especially the server.
6. Apply dev → verify → test → prod.
7. Drop the `deploy_ai_apps ⇒ deploy_tool_apps` note once AI no longer depends on
   `tool_apps` for the server.

---

# Step A — DONE (2026-08-12, dev + test)

`modules/postgres` exists and owns the server, the 3 server-level configurations
and the 3 firewall rules. `tool_apps` creates only its two databases against the
injected `postgres_server_id`. Consumers (`ai_apps` on dev, monitoring alert
scopes on all envs) read `module.postgres[0].server_id` / `.name` / `.fqdn`.

Seven `moved {}` blocks per env root (the 7th, `app_outbound`, is a no-op while
the list is empty). Plan on dev and test: **6 moves, 0 to add, 0 to change,
0 to destroy.** Prod is wired but has never been planned against — its tool stack
is not deployed.

Databases deliberately stayed in `tool_apps` rather than moving too: fewer
addresses to remap, and it already matches the `ai_apps` pattern.

Two traps hit while doing it, both worth avoiding on prod:

- A bulk edit stripped `postgres_sku_name` / `postgres_storage_mb` from the new
  module blocks in test and prod, so they silently fell back to the module
  defaults. The test plan showed `B_Standard_B2s -> B_Standard_B1ms`; prod would
  have been `GP_Standard_D2s_v3 -> B_Standard_B1ms` **and** a storage shrink
  65536 -> 32768, which Flexible Server cannot do. **Read every attribute line in
  the plan, not just the destroy count.**
- Config lost in the `nb/recovery` restore surfaces one environment at a time,
  because gated blocks are invisible where the gate is off (the App Insights Java
  agent envs only appeared in the dev plan). A clean plan per workspace is the
  only reliable check.

# Step B — relocate the server to `ismd-shared-<env>` (NOT started)

Goal: the Azure resource group follows the module. Currently
`resource_group_name = var.tool_resource_group_name` in every env root's
`module "postgres"` block.

`Microsoft.DBforPostgreSQL/flexibleServers` supports a resource-group move
([move-support-resources][move-support]), so this is **not** a backup/restore or a
rebuild. It is an ARM metadata move: the server keeps its name, its data, its
configuration, its firewall rules, and its FQDN
(`ismd-tool-postgres-<env>.postgres.database.azure.com`) — so **no app config
changes and no app restarts**. Child resources move with the parent.

The name stays `ismd-tool-postgres-<env>`. A move does not rename; renaming would
mean a new server and a real data migration. Accept the misleading name or treat
renaming as a separate, much larger piece of work.

**Order matters.** Changing `resource_group_name` in config forces replacement —
destroy + recreate, total data loss. So the Azure move happens FIRST, then state
is re-pointed, then config is changed.

1. Move the resource:

   ```
   az resource move --destination-group ismd-shared-<env> \
     --ids $(az postgres flexible-server show -g ismd-tool-<env> \
             -n ismd-tool-postgres-<env> --query id -o tsv | tr -d '\r\n')
   ```

2. Every affected resource id now embeds the new RG, so Terraform will 404 the old
   ids and propose a destroy/recreate. Re-point state — `terraform state rm` then
   `terraform import` (or `import` blocks, which are reviewable in a plan) — for
   all 8 addresses under `module.<env>[0].module.postgres[0]`:

   - `azurerm_postgresql_flexible_server.tool`
   - `azurerm_postgresql_flexible_server_configuration.unaccent`
   - `azurerm_postgresql_flexible_server_configuration.idle_session_timeout`
   - `azurerm_postgresql_flexible_server_configuration.idle_in_transaction_session_timeout`
   - `azurerm_postgresql_flexible_server_firewall_rule.allow_azure[0]`
   - `azurerm_postgresql_flexible_server_firewall_rule.admin["<ip>"]`
   - plus the 2 databases still in `module.tool_apps[0]`
     (`azurerm_postgresql_flexible_server_database.tool[0]` / `.keycloak[0]`)

   On dev also the AI database in `module.ai_apps[0]`.

3. Change `resource_group_name` to `var.shared_resource_group_name` in that env
   root's `module "postgres"` block.
4. Plan — **must be `0 to destroy`**. The 5 `azurerm_monitor_metric_alert`
   resources scoped to the server will show an in-place update as their `scopes`
   pick up the new id; that is expected and harmless.
5. Dev first, verify apps still connect, then test.

[move-support]: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/move-support-resources#microsoftdbforpostgresql
