# PROD realm config. Apply with: ../terraw.sh switch prod && ../terraw.sh apply
# NOTE: the tool + Keycloak are not deployed in PROD yet — do not apply this
# workspace until PROD Keycloak is up and reachable. Scaffolded for completeness.
# Secrets: TF_VAR_tool_keycloak_admin_password is fetched by terraw from
# ismd-kv-prod/keycloak-admin-password (.terraw-vault-map).

keycloak_url = "https://xn--slovnk-7va.gov.cz"
app_base_url = "https://xn--slovnk-7va.gov.cz/popisujeme"
app_origin   = "https://xn--slovnk-7va.gov.cz"

# No localhost on PROD.

registration_allowed   = false
reset_password_allowed = false
verify_email           = false

smtp_enabled = false

# --- CAAIS (PRODUCTION gateway) ---
# Endpoints pre-filled from the docs. Flip enable_caais to true only once the
# PROD client_id is issued and the container mTLS keystore is live.
enable_caais            = false
caais_client_id         = "" # fill when issued (TF_VAR_caais_client_id or here)
caais_authorization_url = "https://rest-openidconnectapi.caais.gov.cz/oauth2/authorize"
caais_token_url         = "https://cert-openidconnectapi.caais.gov.cz/oauth2/token"
caais_jwks_url          = "https://rest-openidconnectapi.caais.gov.cz/oauth2/jwks"
caais_logout_url        = "https://rest-openidconnectapi.caais.gov.cz/oauth2/endsession"
caais_user_info_url     = "https://rest-openidconnectapi.caais.gov.cz/userinfo"
# Trailing slash is significant — must match the `iss` claim. Verify against the
# PROD .well-known before enabling; the value below mirrors the TEST pattern.
caais_issuer = "https://rest-openidconnectapi.caais.gov.cz/"

# --- NIA (direct Národní bod registration; PRODUCTION národní bod) ---
# From the PRODUCTION discovery document at the non-standard path
# https://nia.identita.gov.cz/fpsts/oidc/openid-configuration (no .well-known).
# Note prod advertises its endpoints in lowercase /fpsts/ where test uses /FPSTS/;
# both hosts answer either casing, but these are the values as published.
# Enabled ahead of the prod stack: this workspace is only applied once PROD Keycloak is up
# (see header), and the registration is live — verified on production NIA 2026-09-30.
enable_nia            = true
nia_client_id         = "https://xn--slovnk-7va.gov.cz/popisujeme" # registered Unikátní URL
nia_authorization_url = "https://nia.identita.gov.cz/fpsts/oidc/authorize"
nia_token_url         = "https://nia.identita.gov.cz/fpsts/oidc/token"
nia_logout_url        = "https://nia.identita.gov.cz/fpsts/oidc/endsession"
nia_user_info_url     = "https://nia.identita.gov.cz/fpsts/oidc/userinfo"
nia_jwks_url          = "https://nia.identita.gov.cz/fpsts/oidc/openid-configuration-jwks"
# Identical to TEST — a URN, and it does NOT distinguish environments.
nia_issuer             = "urn:microsoft:cgg2010:fpsts"
nia_validate_signature = true
# LoA "loalow", same as TEST: on the scope as the floor, and as acr_values from the frontend.
nia_default_scopes = "openid loalow"

# Custom broker from the ismd-tool-keycloak image (NIA's id_token has no sub; attributes
# only when requested). Needs that image on PROD — set in environments/prod/terraform.tfvars.
nia_provider_id      = "nia-oidc"
nia_requested_claims = ["PersonIdentifier", "CurrentGivenName", "CurrentFamilyName"]

# NIA encrypts the id_token to the cert in the PROD registration: ismd-caais-prod-cert
# (verified with a real login 2026-10-02). Its key is NOT Terraform-managed on Keycloak 24
# (it would put the private key in state). After the first apply, import it from
# ismd-kv-prod as an rsa-enc realm key (RSA-OAEP, priority 200), the same as on TEST,
# or every NIA login fails with "Padding error in decryption".

# User profile and account console — same as TEST (see test.tfvars for the reasoning).
manage_user_profile         = true
user_profile_email_required = false
user_profile_names_required = true
account_console_enabled     = false

# The admin-console lockdown imports the realm's security-admin-console client by UUID,
# which only exists once the PROD realm is created. Second pass: read the UUID
# (GET /admin/realms/ismd/clients?clientId=security-admin-console), then set
# disable_realm_admin_console = true and realm_admin_console_client_uuid.
disable_realm_admin_console = false
