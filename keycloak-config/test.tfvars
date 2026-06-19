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
