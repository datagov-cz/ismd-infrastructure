# keycloak-config

Stage-2 Keycloak configuration. Manages what lives **inside** the running
Keycloak — the `ismd` realm and its clients, login/registration flags, and SMTP
settings — via Keycloak's admin REST API.

This root does **not** deploy Keycloak. The Keycloak container itself is an
`azurerm` resource in the per-env state (`modules/tool_apps`). Apply this root
only **after** Keycloak is deployed and reachable.

## State and environments

- Separate backend state from the env states (`key = ismd-keycloak.tfstate`),
  because it's a different plane and a different apply phase.
- Environments are separated by terraform **workspace**, mirroring the main
  state (non-default workspaces stored at `<key>env:<workspace>`). Always select
  an explicit workspace — never apply an environment from `default`.

## Usage

```sh
# from infrastructure/
./terraw.sh switch dev          # selects the dev workspace + per-dir tfvars
cd keycloak-config
terraform init
terraform plan  -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"
```

`terraw.sh` resolves the per-directory tfvars and injects `TF_VAR_*` from the
gitignored `.env.<env>`. Repeat with `test` / `prod` and the matching
`*.tfvars`.

## Configuration

- Committed `*.tfvars` (`dev`, `test`, `prod`) hold non-secret realm settings.
  `terraform.tfvars.example` documents every input.
- **Secrets never go in tfvars** (these files are committed). The Keycloak admin
  password reuses the main state's `TF_VAR_tool_keycloak_admin_password`, already
  set in every `.env.<env>`.
- `local_dev_origins` is DEV-only — it whitelists a local frontend's origin as a
  valid redirect/web origin so devs can log in through deployed DEV Keycloak.
  Keep it empty (`[]`) on TEST/PROD.

## SMTP

`smtp_enabled` stays `false` until the ACS SMTP username/password are delivered
and the sending domain verifies. The credentials are supplied via `TF_VAR_*`,
not committed. See `docs/acs-smtp-setup.md`.

## Provider auth

The `keycloak` provider authenticates as the master-realm `admin-cli` user
against `base_path = /popisujeme/auth` (matches `KC_HTTP_RELATIVE_PATH` on the
container). The `azurerm` provider is present for pulling SMTP creds from Key
Vault later and is otherwise unused.
