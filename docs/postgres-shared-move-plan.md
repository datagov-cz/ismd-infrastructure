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
