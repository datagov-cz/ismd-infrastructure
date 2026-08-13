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
caais_logout_url        = "https://rest-openidconnectapi.caais.gov.cz/oauth2/end_session"
caais_user_info_url     = "https://rest-openidconnectapi.caais.gov.cz/userinfo"
# Trailing slash is significant — must match the `iss` claim. Verify against the
# PROD .well-known before enabling; the value below mirrors the TEST pattern.
caais_issuer = "https://rest-openidconnectapi.caais.gov.cz/"
