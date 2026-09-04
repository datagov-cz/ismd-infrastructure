# Per-app database user separation

Goal: stop every app logging in as the server admin `ismdadmin`. Give each app a
dedicated LOGIN role that can reach **only its own database**, so a compromised app
can't touch another app's data (notably Keycloak's identity tables).

## Current state (all envs)

One Postgres 16 Flexible Server `ismd-tool-postgres-<env>`, three databases, all
apps authenticating as `ismdadmin`:

| Database      | App          | Schema        | Migrations       |
|---------------|--------------|---------------|------------------|
| `ismd_tool_db`| tool-backend | `ismd_schema` | Liquibase (in-app at boot) |
| `keycloak_db` | Keycloak     | `public`      | Keycloak-managed |
| `ismd_ai`     | ismd-ai      | `public`      | app-managed      |

Validator has no Postgres.

## Target state

| Role (LOGIN)       | Reaches       | Owns                    |
|--------------------|---------------|-------------------------|
| `ismd_tool_app`    | `ismd_tool_db`| `ismd_schema` + objects |
| `ismd_keycloak_app`| `keycloak_db` | its objects             |
| `ismd_ai_app`      | `ismd_ai`     | its objects             |
| `ismdadmin` (keep) | all (admin)   | break-glass / migrations fallback |

Because each app owns its own database it can still run its own migrations
(Liquibase for the tool). Isolation comes from `REVOKE CONNECT ... FROM PUBLIC`
plus granting CONNECT only to the owning role — by default any role can connect
to any database, which is what we're closing.

## Why this is non-disruptive until cutover

The SQL phase only **adds** roles and **transfers ownership** away from `ismdadmin`.
Apps keep running because they still connect as `ismdadmin`, which stays a member
of each new role (so it retains full access). Nothing breaks until you flip an
app's `POSTGRES_USER`/`APP_DB_USER` in Terraform (the cutover phase), which you do
one app at a time.

## Order

Do the whole thing on **dev** first and validate by logging in directly as each
new role. Then **test**, then **prod**. Within an env, cut apps over lowest-risk
first: **ismd-ai → tool-backend → keycloak** (keycloak last; auth-outage risk).

---

## Phase 1 — create roles + transfer ownership (pgAdmin, as `ismdadmin`)

For each app run its script. **Watch which database the pgAdmin query tool is
connected to** — each script has a "connect to X" marker; the ownership/grant
part must run inside the target DB, not `postgres`.

1. Generate three strong passwords, store them in Key Vault (rides the existing
   secrets-config plan), and substitute the `<<...>>` placeholders. **Do not commit
   real passwords** — leave the placeholders in the repo copy.
2. Run `01-tool.sql`, `02-keycloak.sql`, `03-ai.sql`.
3. Run `99-verify.sql`, then open a **new pgAdmin connection as each new role** and
   confirm: it can query its own DB, and is *refused* on the other two.

Keycloak's `REASSIGN OWNED` takes brief locks on its tables — run `02-keycloak.sql`
in a quiet window.

## Phase 2 — cut each app over (Terraform + redeploy)

The Terraform is already wired (DEV). Each app's DB username now comes from a
variable that **defaults to the admin login**, so the code is a no-op until an env
sets it. Cutover is a per-env variable flip in `.env.dev` (or dev tfvars), then
`./terraw.sh apply`. The password already flows through per-app KV secret ids, so
no code change is needed there — just repoint/reseed the secret value.

| App          | Flip this var (empty/admin → dedicated role) | Password secret to repoint |
|--------------|----------------------------------------------|----------------------------|
| ismd-ai      | `ai_db_user = "ismd_ai_app"`                 | `ai_postgres_password_kv_secret_id` → the `ismd_ai_app` secret |
| tool-backend | `tool_backend_db_user = "ismd_tool_app"`     | `tool_postgres_password_kv_secret_id` → the `ismd_tool_app` secret |
| keycloak     | `tool_keycloak_db_user = "ismd_keycloak_app"`| `tool_keycloak_db_password_kv_secret_id` → the `ismd_keycloak_app` secret |

Wiring reference (empty tool_* var → `postgres_admin_user`; `ai_db_user` defaults
to `ismdadmin`):
- tool-backend `POSTGRES_USER` — `modules/tool_apps/backend.tf` (`var.backend_db_user`)
- keycloak `KC_DB_USERNAME` — `modules/tool_apps/keycloak.tf` (`var.keycloak_db_user`)
- ismd-ai `APP_DB_USER` — `environments/dev/main.tf` (`var.ai_db_user`)

Per app: seed the role's password into its KV secret (so the app authenticates as
the new role, not admin), flip the username var, point the password KV secret id at
the per-app secret, `./terraw.sh apply`, redeploy. Validate the app boots and does a
real read+write. **Roll back = revert the var (+ password secret id) and redeploy** —
the admin login keeps working throughout, and `ismdadmin` stays a member of each new
role until Phase 3, so even the dedicated roles retain full access.

> Note: today tool-backend and keycloak passwords may point at the same admin
> `postgres-password` secret. Splitting users means each must resolve to **its own
> role's password** — give keycloak its own secret value before flipping it.

TEST/PROD are intentionally not threaded yet (DEV-gated). Extending them is
mechanical: add the same `tool_backend_db_user` / `tool_keycloak_db_user` forwards
to the test/prod module blocks in `infrastructure/main.tf` and their env
`variables.tf`, mirroring the DEV wiring.

## Phase 3 — (optional) tighten

Once every app is cut over and stable, you may `REVOKE ismd_tool_app FROM ismdadmin`
(and the others) so admin no longer acts *as* the app roles. Keep it granted if you
want admin break-glass into each DB. Trade-off, your call.

## Verification checklist per env

- [ ] `SELECT rolname FROM pg_roles WHERE rolname LIKE 'ismd_%_app';` shows 3 roles
- [ ] PUBLIC has no CONNECT on any of the 3 DBs (`99-verify.sql`)
- [ ] Each role connects to its own DB only (direct pgAdmin login test)
- [ ] Each app cut over, boots, and can read+write its DB
- [ ] Keycloak login works after its cutover
