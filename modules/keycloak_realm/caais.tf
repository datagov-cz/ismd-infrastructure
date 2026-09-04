# CAAIS identity provider (Czech national identity gateway) — brokered OIDC login.
#
# Auth is mTLS (RFC 8705 tls_client_auth): CAAIS matches the client cert Keycloak
# presents on the outbound token call against the cert registered in the AIS
# config — client_secret is unused (a non-empty dummy is kept only because some
# flows expect the field populated). The cert itself is NOT configured here; it is
# a server-global outbound keystore on the Keycloak container (see the tool_apps
# module: KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE).
#
# Kept inert until enable_caais = true AND the endpoint URLs + client_id are set
# per env (tfvars). The token endpoint lives on a SEPARATE mTLS host (cert-...)
# from authorize/jwks (rest-...); that split is intentional and required.

resource "keycloak_oidc_identity_provider" "caais" {
  count = var.enable_caais ? 1 : 0

  realm        = keycloak_realm.ismd.id
  alias        = "caais"
  display_name = "CAAIS (Identita občana)"

  authorization_url = var.caais_authorization_url
  token_url         = var.caais_token_url # cert- host (mTLS)
  jwks_url          = var.caais_jwks_url
  user_info_url     = var.caais_user_info_url
  issuer            = var.caais_issuer

  # CAAIS end_session (rest- host) — Keycloak propagates logout to CAAIS, so the
  # user can switch identity instead of being silently re-authenticated. Empty =
  # no IdP logout. This is a top-level attribute; it is rejected in extra_config.
  logout_url = var.caais_logout_url

  client_id = var.caais_client_id
  # Empty: CAAIS ignores client_secret entirely (auth is the TLS client cert).
  # Matches the working local realm export.
  client_secret = ""

  default_scopes = var.caais_default_scopes # "openid profile"

  # FORCE: refresh mapped attributes from CAAIS on every login (keeps names
  # current) rather than importing once.
  sync_mode = "FORCE"

  # Logout has to reach CAAIS, otherwise its session survives our logout and the next
  # login is silently re-authenticated as the same person — no way to switch account.
  # Two things are needed for that:
  #
  #   backchannel_supported = false — the provider defaults to true, which makes
  #     Keycloak POST to logout_url server-to-server. CAAIS's end_session is a
  #     FRONT-CHANNEL redirect endpoint, so the backchannel POST silently no-ops.
  #     false makes Keycloak redirect the browser there instead.
  #
  #   store_token = true — CAAIS documents id_token_hint as mandatory on end_session,
  #     and Keycloak can only send it if it kept the brokered id_token. Costs us
  #     national-identity tokens at rest in the Keycloak DB, which is why it was off;
  #     testing showed logout silently failing without it.
  backchannel_supported = false
  store_token           = true

  trust_email        = false
  validate_signature = var.caais_validate_signature
  hide_on_login_page = false

  # clientAuthMethod: CAAIS documents tls_client_auth (RFC 8705), but that is not a
  # value Keycloak's OIDC broker implements — it only offers client_secret_{post,
  # basic,jwt} and private_key_jwt. That is fine: tls_client_auth means "authenticate
  # via the TLS client certificate", which happens at the TRANSPORT layer via the
  # server-global outbound keystore (see tool_apps/keycloak.tf). clientAuthMethod
  # only governs the token-request BODY, so client_secret_post with an empty secret
  # sends client_id and lets the cert do the authenticating — exactly what CAAIS
  # checks. Matches the proven local setup (tool-backend/docker/keycloak/ismd-realm.json).
  #
  extra_config = {
    clientAuthMethod = "client_secret_post"
    pkceEnabled      = "true"
    pkceMethod       = "S256"
  }
}

# --- Claim mappers (scope: openid profile) ---

resource "keycloak_attribute_importer_identity_provider_mapper" "caais_first_name" {
  count = var.enable_caais ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "caais-given-name"
  identity_provider_alias = keycloak_oidc_identity_provider.caais[0].alias
  claim_name              = "given_name"
  user_attribute          = "firstName"

  extra_config = {
    syncMode = "INHERIT"
  }
}

resource "keycloak_attribute_importer_identity_provider_mapper" "caais_last_name" {
  count = var.enable_caais ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "caais-family-name"
  identity_provider_alias = keycloak_oidc_identity_provider.caais[0].alias
  claim_name              = "family_name"
  user_attribute          = "lastName"

  extra_config = {
    syncMode = "INHERIT"
  }
}

resource "keycloak_user_template_importer_identity_provider_mapper" "caais_username" {
  count = var.enable_caais ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "caais-username"
  identity_provider_alias = keycloak_oidc_identity_provider.caais[0].alias
  template                = "$${CLAIM.username}"

  extra_config = {
    syncMode = "INHERIT"
  }
}
