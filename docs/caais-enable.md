# Runbook — Enable CAAIS brokered login (Keycloak, mTLS)

CAAIS is a brokered OIDC identity provider on the `ismd` realm. Auth to CAAIS is
**mTLS** (RFC 8705 `tls_client_auth`): Keycloak presents a client certificate on the
outbound token call and CAAIS matches it against the cert registered in the AIS
config. There is **no** `client_secret`.

Keycloak's OIDC broker has no `tls_client_auth` option, and it doesn't need one — the
cert is presented at the **transport** layer by the server-global outbound keystore
(`KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE*`, the env form of the
`--spi-connections-http-client-default-client-keystore*` flags). `clientAuthMethod`
only governs the token-request body, so it's `client_secret_post` with an empty
secret — matching the proven local setup.

The integration is coded and **inert**; everything below is data/ops. Two roots:

- `infrastructure/` (per-env stack) — Keycloak container + the mTLS keystore
  (init container decodes a base64 PFX from Key Vault into a shared volume).
- `infrastructure/keycloak-config/` — the realm-side identity provider + mappers.

Endpoints, issuer, userinfo and logout URL are pre-filled per env in
`keycloak-config/*.tfvars`. Scope is `openid profile`.

## Certificate model

The CAAIS cert lives in the per-env vault (`ismd-kv-<env>`) as a **KV Certificate
object** with `issuer: Unknown` (external CA):

1. KV generates the keypair **in-vault** and emits a CSR — the private key never
   leaves the vault.
2. The CSR goes to the CAAIS CA for signing.
3. The signed cert is **merged** back; the certificate object completes.
4. KV then auto-exposes a companion secret at `…/secrets/<cert-name>` whose value is
   the full **PFX (key + cert) in base64** — this is what `caais_p12_kv_secret_id`
   points at, and what the init container decodes.

The `keycloak_kv` identity reads it; its access policy is created unconditionally in
the env root, so the grant always precedes the secret reference at apply.

> The CA must sign **our** CSR (the one KV emitted) and return the `.cer`/`.crt`
> **file**. A cert issued from someone else's CSR pairs with someone else's private
> key and is useless to us — `certificate pending merge` will reject it, since KV
> only accepts a cert matching the key it is holding.

## Prerequisites

- Pending cert exists in `ismd-kv-<env>` (Certificates → shows under "In progress").
- The **signed cert file**, issued from that pending cert's CSR.
- The issued **client_id** for the env's AIS.
- The AIS configured: return/allowed-return URL = the broker endpoint
  (`./terraw.sh output tool_caais_redirect_uri`), logout URL = same + `/logout_response`,
  and the **Uživatel** access role assigned to users (else CAAIS refuses the login).

## Step 1 — merge the signed cert

`az keyvault certificate pending merge --vault-name ismd-kv-<env> --name <cert-name> --file signed.crt`

The cert flips to "Completed"/enabled. Grab the secret id (versionless, so rotation
needs no tfvars change):

`az keyvault secret show --vault-name ismd-kv-<env> --name <cert-name> --query id -o tsv`

## Step 2 — seed the keystore password

KV exports the PFX **unprotected**, but Keycloak cannot use an empty password:
Quarkus reads an empty env var as *unset*, passes `null` into `loadKeyMaterial`, and
Java throws `UnrecoverableKeyException: Get Key failed: ... "password" is null`.

So the init container **re-wraps** the PFX with a real password (hence the
openssl-capable `caais_keystore_init_image`), and Keycloak opens it with the same
one. Seed it:

`az keyvault secret set --vault-name ismd-kv-<env> --name caais-keystore-pw --value "$(openssl rand -base64 24)"`

> One password only — `openssl pkcs12 -export` protects the whole file with a single
> password, so there is no separate "key password" despite Keycloak exposing two
> options. Both are set from this one value.
>
> Its security value is modest: it protects an ephemeral in-pod EmptyDir file, and
> the password sits in the same pod. It exists because Keycloak requires a non-null
> one, not because it guards much.

## Step 3 — wire the keystore (env stack)

Set in the env stack (`.env.<env>` `TF_VAR_…` or the gitignored `terraform.tfvars`):

- `tool_caais_client_id` — the AIS shortcut (`ISMD_dev`, `ISMD_stage`)
- `tool_caais_p12_kv_secret_id` — the cert's **versionless** secret id from Step 1,
  e.g. `https://ismd-kv-dev.vault.azure.net/secrets/ismd-dev-caais-test-cert`
- `tool_caais_keystore_password_kv_secret_id` — e.g.
  `https://ismd-kv-dev.vault.azure.net/secrets/caais-keystore-pw`

All three are required for the keystore to render; any empty leaves it inert.

Then `./terraw.sh switch <env> && ./terraw.sh apply`. This adds the init container,
the shared volume, the keystore env vars, and the KV secret references. Keycloak
restarts with the outbound client cert available. All of it stays inert while any of
those values are empty.

## Step 4 — enable the realm identity provider

In `keycloak-config/<env>.tfvars` set `enable_caais = true` and `caais_client_id`.
Then, from `infrastructure/keycloak-config`:

`../terraw.sh switch <env> && ../terraw.sh apply`

Creates the `caais` OIDC identity provider + the given_name/family_name/username
mappers.

## Step 5 — verify & watch-outs

- Trigger a login; confirm the broker redirect to CAAIS and a successful token
  exchange (the mTLS call). Check Keycloak logs for TLS handshake errors.
- **Server truststore:** if the token host (`cert-openidconnectapi…`) chains to a CA
  not in the JVM default truststore, the outbound TLS fails. Fix with
  `--truststore-paths` / `KC_TRUSTSTORE_PATHS`. Verify on DEV first.
- **`store_token = false`** on the IdP: if logout to CAAIS silently no-ops, Keycloak
  may not be sending `id_token_hint` — flip to `true` only if testing shows that.
- Scope: widen `caais_default_scopes` later with a plain apply (users re-login to
  pick up new claims). No cert impact. The local setup used `openid profile role`.

## Rotation

Renew the cert in KV (new version) and re-merge the newly signed cert, then restart
the Keycloak revision — the secret id is versionless, so no tfvars change. **The new
cert must also be uploaded to the AIS Authentication slot**, since CAAIS matches the
presented cert against its stored copy. If the AIS accepts multiple certs, add the
new one before cutting over to avoid downtime.

## Disable / rollback

Set `enable_caais = false` in `keycloak-config/<env>.tfvars` (removes the IdP), and
blank `tool_caais_p12_kv_secret_id` in the env stack (removes the keystore wiring).
