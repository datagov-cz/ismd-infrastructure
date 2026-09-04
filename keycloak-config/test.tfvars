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

# --- CAAIS (TEST env pointed at the PRODUCTION gateway, 2026-08-12) ---
#
# TEST talks to PRODUCTION CAAIS, per DIA supervisor decision. The stage AIS
# (ISMD_stage) was not usable; rather than run a second identity provider, this
# repoints the existing `caais` IdP. Two IdPs would not have worked: the client
# cert is presented by Keycloak's SERVER-GLOBAL outbound keystore
# (KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE*), not per-IdP, so both
# would present the same cert and the stage one would fail every token call.
# Keeping the alias `caais` also preserves existing federated user links.
#
# The matching client cert is the PRODUCTION cert copied into ismd-kv-test as
# `ismd-test-caais-prod-cert` — CAAIS matches the presented cert against the cert
# registered for this AIS, so cert and client_id must move together.
#
# To revert to the stage gateway: restore the commented block below AND repoint
# tool_caais_p12_kv_secret_id back to ismd-test-caais-test-cert (which is still in
# the vault, valid to 2028-08-01).
enable_caais = true
# The PRODUCTION AIS shortcut ("zkratka") — the AIS registered against
# ismd-caais-prod-cert. Not a secret. (The stage AIS was ISMD_stage.)
caais_client_id         = "ISMD"
caais_authorization_url = "https://rest-openidconnectapi.caais.gov.cz/oauth2/authorize"
caais_token_url         = "https://cert-openidconnectapi.caais.gov.cz/oauth2/token"
caais_jwks_url          = "https://rest-openidconnectapi.caais.gov.cz/oauth2/jwks"
caais_logout_url        = "https://rest-openidconnectapi.caais.gov.cz/oauth2/end_session"
caais_user_info_url     = "https://rest-openidconnectapi.caais.gov.cz/userinfo"
caais_issuer            = "https://rest-openidconnectapi.caais.gov.cz/" # trailing slash is significant — must match the `iss` claim

# Previous TEST → CAAIS-test wiring, kept for the way back:
# CAAIS calls our TEST environment "stage" — hence ISMD_stage, not ISMD_test.
# caais_client_id         = "ISMD_stage"
# caais_authorization_url = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/authorize"
# caais_token_url         = "https://cert-openidconnectapi.caais-test-ext.gov.cz/oauth2/token"
# caais_jwks_url          = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/jwks"
# caais_logout_url        = "https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/end_session"
# caais_user_info_url     = "https://rest-openidconnectapi.caais-test-ext.gov.cz/userinfo"
# caais_issuer            = "https://rest-openidconnectapi.caais-test-ext.gov.cz/"

# --- NIA (direct Národní bod registration; TEST národní bod) ---
# From NIA's discovery document at the non-standard path
# https://tnia.identita.gov.cz/fpsts/oidc/openid-configuration (no .well-known).
# See NIA-INTEGRATION-REQUEST.md.
enable_nia            = false
nia_client_id         = "" # = "https://xn--slovnk-test-scb.dia.gov.cz/popisujeme" once registered
nia_authorization_url = "https://tnia.identita.gov.cz/FPSTS/oidc/authorize"
nia_token_url         = "https://tnia.identita.gov.cz/FPSTS/oidc/token"
nia_logout_url        = "https://tnia.identita.gov.cz/FPSTS/oidc/endsession"
nia_user_info_url     = "https://tnia.identita.gov.cz/FPSTS/oidc/userinfo"
nia_jwks_url          = "https://tnia.identita.gov.cz/FPSTS/oidc/openid-configuration-jwks"
# A URN, not a URL — and the SAME on test and prod.
nia_issuer             = "urn:microsoft:cgg2010:fpsts"
nia_validate_signature = true
# "profile" is not a supported NIA scope. Append the LoA scope once DIA decides.
nia_default_scopes = "openid"
