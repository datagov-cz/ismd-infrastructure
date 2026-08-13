# Tool Apps Module — Keycloak and CAAIS variable declarations

variable "deploy_keycloak" {
  description = "Whether to deploy Keycloak as part of tool apps"
  type        = bool
  default     = true
}

variable "enable_caais" {
  description = "Whether CAAIS integration is enabled for Keycloak"
  type        = bool
  default     = true
}

# Keycloak container image
variable "keycloak_image" {
  description = "Base container image URL for Keycloak (without tag)"
  type        = string
  default     = "quay.io/keycloak/keycloak"
}

variable "keycloak_image_tag" {
  description = "Tag for the Keycloak container image"
  type        = string
  default     = "24.0.2"
}

variable "keycloak_app_name" {
  description = "Name of the Keycloak container app"
  type        = string
  default     = "ismd-tool-keycloak"
}

# Keycloak admin credentials
variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
  default     = ""
}

# Keycloak hostname and realm
variable "keycloak_hostname" {
  description = "Optional Keycloak hostname for admin and public endpoints"
  type        = string
  default     = ""
}

variable "keycloak_realm" {
  description = "Keycloak realm used by tool frontend/backend"
  type        = string
  default     = "ismd"
}

variable "keycloak_issuer_uri" {
  description = "Optional explicit issuer URI. If empty, issuer is derived from deployed Keycloak and realm."
  type        = string
  default     = ""
}

# OIDC client
variable "keycloak_client_id" {
  description = "OIDC client ID used by tool frontend/backend"
  type        = string
  default     = "ismd-app"
}

variable "keycloak_client_secret" {
  description = "OIDC client secret used by tool frontend/backend"
  type        = string
  sensitive   = true
  default     = ""
}

# Keycloak identity-provider alias to jump straight to, bypassing the Keycloak
# login page. Injected as KEYCLOAK_IDP_HINT into the frontend; auth.ts adds it as
# kc_idp_hint on the authorization request only when non-empty. Empty = show the
# Keycloak login page (local accounts + IdP buttons). Set to "caais" per env.
variable "keycloak_idp_hint" {
  description = "Keycloak IdP alias to redirect straight to (e.g. \"caais\"), skipping the Keycloak login page. Empty shows the Keycloak page."
  type        = string
  default     = ""
}

# CAAIS federation
variable "caais_client_id" {
  description = "CAAIS client ID configured in Keycloak"
  type        = string
  default     = ""
}

# CAAIS mTLS client keystore (RFC 8705 tls_client_auth).
# CAAIS authenticates the AIS by matching the client cert presented on the outbound
# mTLS token call against the cert registered in its AIS config — client_secret is
# unused. The cert+key are a PKCS12 that Keycloak's outbound HTTP client presents;
# it is delivered as a base64 KV secret, decoded to a file by an init container, and
# referenced via KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE*.
#
# These point at the per-env vault (ismd-kv-<env>). The intended source is a KV
# CERTIFICATE object: the key is generated in-vault, the CSR signed by the CAAIS CA,
# and the signed cert merged back — the private key never leaves the vault. A KV
# certificate auto-exposes a companion secret at …/secrets/<cert-name> whose value is
# the full PFX in base64, so caais_p12_kv_secret_id points there. Values are seeded
# out-of-band; the keycloak_kv identity's read grant is created in the env root.
#
# NOTE: KV exports that PFX with an EMPTY password, but Keycloak requires both
# password options whenever client-keystore is set. Empty strings may satisfy it
# (Java accepts an empty keystore password) — if not, the p12 must be re-wrapped
# with a password (needs an openssl-capable init image, not busybox).
#
# Leave empty to keep CAAIS mTLS inert even when enable_caais is true.

variable "caais_p12_kv_secret_id" {
  description = "Key Vault secret id (versionless) yielding the base64 CAAIS client PKCS12 — normally the auto-exposed secret of the CAAIS KV Certificate object in ismd-kv-<env>. Empty = mTLS keystore not yet wired."
  type        = string
  default     = ""
}

# KV exports the certificate's PFX with an EMPTY password, but Keycloak cannot use
# one: Quarkus treats an empty env var as UNSET, so it passes null into
# loadKeyMaterial and Java throws
#   UnrecoverableKeyException: Get Key failed: ... "password" is null
# So the init container re-wraps the PFX with a real password, which both it and
# Keycloak read from here. One password only — `openssl pkcs12 -export` protects the
# whole file with a single password; a separate key password isn't a real thing.
variable "caais_keystore_password" {
  description = "Inline CAAIS PKCS12 password used to re-wrap the KV export and open it in Keycloak. Must be non-empty when the keystore is wired. Ignored when caais_keystore_password_kv_secret_id is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "caais_keystore_password_kv_secret_id" {
  description = "Key Vault secret id for the CAAIS PKCS12 password. Empty = use the inline caais_keystore_password."
  type        = string
  default     = ""
}

variable "caais_keystore_init_image" {
  description = "Image for the init container that decodes the KV PFX and re-wraps it with a password. Needs a shell, base64 AND openssl (the stock ubi-micro Keycloak image has none of them; busybox has no openssl). Swap for a leaner openssl-capable image if the pull time bothers you."
  type        = string
  default     = "mcr.microsoft.com/azure-cli:latest"
}

# Keycloak database (uses shared PostgreSQL when deploy_postgres = true)
variable "keycloak_db_name" {
  description = "Database name used by Keycloak"
  type        = string
  default     = "keycloak_db"
}

variable "keycloak_postgres_url" {
  description = "External JDBC URL for Keycloak database when deploy_postgres=false"
  type        = string
  default     = ""
}

variable "keycloak_postgres_user" {
  description = "External PostgreSQL username for Keycloak when deploy_postgres=false"
  type        = string
  default     = ""
}

# Per-app user separation (see infrastructure/db/user-separation/). Keycloak logs
# in as this dedicated LOGIN role instead of the server admin. Empty = fall back to
# postgres_admin_user (current behaviour). Cut Keycloak over LAST — a bad flip is an
# auth outage. Set to "ismd_keycloak_app" AFTER 02-keycloak.sql and pointing the
# keycloak db password secret at that role's password.
variable "keycloak_db_user" {
  description = "Dedicated Postgres LOGIN role for Keycloak. Empty = use the admin login. Set to 'ismd_keycloak_app' once db/user-separation Phase 1 is applied and the keycloak-db-password secret holds that role's password."
  type        = string
  default     = ""
}

variable "keycloak_postgres_password" {
  description = "External PostgreSQL password for Keycloak when deploy_postgres=false"
  type        = string
  sensitive   = true
  default     = ""
}
