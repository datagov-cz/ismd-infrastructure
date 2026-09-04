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
caais_logout_url        = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/endsession"
caais_user_info_url     = "https://rest-openidconnectapi.caais-test-ext.gov.cz/userinfo"
caais_issuer            = "https://rest-openidconnectapi.caais-test-ext.gov.cz/" # trailing slash is significant — must match the `iss` claim

# --- NIA (direct Národní bod registration; uses the TEST národní bod) ---
# Values taken from NIA's discovery document, which lives at a NON-STANDARD path:
#   https://tnia.identita.gov.cz/fpsts/oidc/openid-configuration
# (no .well-known). It supersedes the SeP handbook, which lists only 4 of the 6
# endpoints. Flip enable_nia to true once the "Unikátní URL" below is registered
# and TF_VAR_nia_client_secret is set. See NIA-INTEGRATION-REQUEST.md.
enable_nia            = false
nia_client_id         = "" # = "https://oha03.dia.gov.cz/popisujeme" once registered
nia_authorization_url = "https://tnia.identita.gov.cz/FPSTS/oidc/authorize"
nia_token_url         = "https://tnia.identita.gov.cz/FPSTS/oidc/token"
nia_logout_url        = "https://tnia.identita.gov.cz/FPSTS/oidc/endsession"
nia_user_info_url     = "https://tnia.identita.gov.cz/FPSTS/oidc/userinfo"
nia_jwks_url          = "https://tnia.identita.gov.cz/FPSTS/oidc/openid-configuration-jwks"
# A URN, not a URL — and the SAME on test and prod, so it cannot tell the two apart.
nia_issuer             = "urn:microsoft:cgg2010:fpsts"
nia_validate_signature = true
# "profile" is not a supported NIA scope. Append the LoA scope (loalow /
# loasubstantial / loahigh) once DIA settles the required level.
nia_default_scopes = "openid"
