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
