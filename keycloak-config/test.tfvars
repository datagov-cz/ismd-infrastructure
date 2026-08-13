# TEST realm config. Apply with: ../terraw.sh switch test && ../terraw.sh apply
# Secrets (keycloak_admin_password) come from .env.test as TF_VAR_keycloak_admin_password.

keycloak_url = "https://xn--slovnk-test-scb.dia.gov.cz"
app_base_url = "https://xn--slovnk-test-scb.dia.gov.cz/popisujeme"
app_origin   = "https://xn--slovnk-test-scb.dia.gov.cz"

# No localhost on TEST — local_dev_origins defaults to [] (DEV-only convenience).

# Registration / email off until decided / SMTP live.
registration_allowed   = false
reset_password_allowed = false
verify_email           = false

smtp_enabled = false

# --- CAAIS (TEST gateway) ---
enable_caais = true
# CAAIS calls our TEST environment "stage" — hence ISMD_stage, not ISMD_test.
caais_client_id         = "ISMD_stage" # the AIS shortcut ("zkratka") in CAAIS; not a secret
caais_authorization_url = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/authorize"
caais_token_url         = "https://cert-openidconnectapi.caais-test-ext.gov.cz/oauth2/token"
caais_jwks_url          = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/jwks"
caais_logout_url        = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/end_session"
caais_user_info_url     = "https://rest-openidconnectapi.caais-test-ext.gov.cz/userinfo"
caais_issuer            = "https://rest-openidconnectapi.caais-test-ext.gov.cz/" # trailing slash is significant — must match the `iss` claim
