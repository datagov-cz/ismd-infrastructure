# DEV example. Copy to a real tfvars (gitignored) or pass via TF_VAR_ env.
# Secrets (keycloak_admin_password, smtp_password) should come from env or a
# secrets file, never committed.

keycloak_url      = "https://oha03.dia.gov.cz"
app_base_url      = "https://oha03.dia.gov.cz/popisujeme"
app_origin        = "https://oha03.dia.gov.cz"
local_dev_origins = ["http://localhost:3000"]

# keycloak_admin_user defaults to "admin"
# keycloak_admin_password = "..."   # prefer TF_VAR_keycloak_admin_password

# DEV-only: 24h sessions so a dev stays logged in across a full day of testing.
# Matches what was already set live. TEST/PROD keep the 10h default.
sso_session_idle_timeout = "24h"
sso_session_max_lifespan = "24h"

# Registration / email — keep off until decided / SMTP live.
registration_allowed   = false
reset_password_allowed = false
verify_email           = false

# SMTP — flip on only after the supervisor delivers the ACS SMTP username/
# password (Layer A). Until then leave smtp_enabled = false.
smtp_enabled = false
# smtp_from     = "DoNotReply@<guid>.azurecomm.net"
# smtp_username = "ismd-acs.<entra-app-id>.<tenant-id>"   # via TF_VAR_
# smtp_password = "..."                                    # via TF_VAR_

# --- CAAIS (uses the TEST gateway; no separate CAAIS dev environment) ---
# Endpoints are known from the docs and safe to pre-fill. Flip enable_caais to
# true only once the client_id is issued and the container mTLS keystore is live.
enable_caais            = true
caais_client_id         = "ISMD_dev" # the AIS shortcut ("zkratka") in CAAIS; not a secret
caais_authorization_url = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/authorize"
caais_token_url         = "https://cert-openidconnectapi.caais-test-ext.gov.cz/oauth2/token"
caais_jwks_url          = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/jwks"
caais_logout_url        = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/end_session"
caais_user_info_url     = "https://rest-openidconnectapi.caais-test-ext.gov.cz/userinfo"
caais_issuer            = "https://rest-openidconnectapi.caais-test-ext.gov.cz/" # trailing slash is significant — must match the `iss` claim
