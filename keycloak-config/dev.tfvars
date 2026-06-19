# DEV example. Copy to a real tfvars (gitignored) or pass via TF_VAR_ env.
# Secrets (keycloak_admin_password, smtp_password) should come from env or a
# secrets file, never committed.

keycloak_url      = "https://oha03.dia.gov.cz"
app_base_url      = "https://oha03.dia.gov.cz/popisujeme"
app_origin        = "https://oha03.dia.gov.cz"
local_dev_origins = ["http://localhost:3000"]

# keycloak_admin_user defaults to "admin"
# keycloak_admin_password = "..."   # prefer TF_VAR_keycloak_admin_password

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
