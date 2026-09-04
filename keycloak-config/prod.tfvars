# PROD realm config. Apply with: ../terraw.sh switch prod && ../terraw.sh apply
# NOTE: the tool + Keycloak are not deployed in PROD yet — do not apply this
# workspace until PROD Keycloak is up and reachable. Scaffolded for completeness.
# Secrets (keycloak_admin_password) come from .env.prod as TF_VAR_keycloak_admin_password.

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
# Do not enable: the tool stack (and Keycloak) is not deployed to PROD.
enable_nia            = false
nia_client_id         = "" # = "https://xn--slovnk-7va.gov.cz/popisujeme" once registered
nia_authorization_url = "https://nia.identita.gov.cz/fpsts/oidc/authorize"
nia_token_url         = "https://nia.identita.gov.cz/fpsts/oidc/token"
nia_logout_url        = "https://nia.identita.gov.cz/fpsts/oidc/endsession"
nia_user_info_url     = "https://nia.identita.gov.cz/fpsts/oidc/userinfo"
nia_jwks_url          = "https://nia.identita.gov.cz/fpsts/oidc/openid-configuration-jwks"
# Identical to TEST — a URN, and it does NOT distinguish environments.
nia_issuer             = "urn:microsoft:cgg2010:fpsts"
nia_validate_signature = true
nia_default_scopes     = "openid"
