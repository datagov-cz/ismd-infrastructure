# NIA identity provider (Národní bod / Identita občana) — brokered OIDC login.
#
# This is a DIRECT registration with the národní bod, parallel to the CAAIS
# integration in caais.tf, which reaches the same identity source indirectly.
# Both can exist on the realm; they are separate IdPs with separate aliases.
#
# Endpoints are published in the SeP handbook (ch. 8.2) and pre-filled per env in
# keycloak-config/*.tfvars. Kept inert until enable_nia = true AND nia_client_id
# is set — the client_id is the "Unikátní URL" registered on identita.gov.cz, so
# it does not exist until registration is done.
#
# NIA *does* publish a discovery document, at a NON-STANDARD path — no .well-known:
#
#   https://tnia.identita.gov.cz/fpsts/oidc/openid-configuration   (test)
#   https://nia.identita.gov.cz/fpsts/oidc/openid-configuration    (prod)
#
# It is the authority for everything below and contradicts the SeP handbook in
# several places (the handbook lists only 4 endpoints; discovery has 6). Re-read it
# before changing anything here. What it establishes:
#
#   - token_endpoint_auth_methods_supported = ["client_secret_post"] ONLY. NOT mTLS
#     like CAAIS: no outbound keystore, no init container, no certificate.
#     But NO SECRET IS ISSUED either. The NIA developer wiki ("OpenID Connect
#     protokol", Token endpoint) lists the token request as client_id, grant_type,
#     code — plus redirect_uri and code_verifier, both "hodnota je ignorována".
#     No client_secret anywhere on the page, and the registration form issues none.
#     NIA identifies the SeP by client_id + the registered redirect_uri, so
#     nia_client_secret stays empty. Confirmed 2026-09-15: the token call succeeds
#     with client_id + code alone.
#   - jwks_uri exists, so signature validation is on by default here.
#   - NO id_token_encryption_alg_values_supported — but NIA DOES encrypt the
#     id_token anyway (verified 2026-09-15): JWE, alg RSA-OAEP, enc A256CBC-HS512,
#     no kid. It encrypts to the certificate uploaded in registration field 12, and
#     Keycloak decrypts with the realm's active RSA-OAEP key. If those two do not
#     pair, login fails with "Padding error in decryption".
#   - NO code_challenge_methods_supported → PKCE is NOT advertised; see below.
#   - Claim names are eIDAS-style (CurrentGivenName, …), NOT the OIDC standard
#     given_name/family_name that CAAIS uses. See the mappers at the bottom.
#   - scopes_supported has NO "profile" — requesting it may be rejected.
#
# Verified live 2026-09-16, and why the stock "oidc" provider cannot work:
#   - The id_token has NO "sub". Keycloak (24.0.2 and 26.7.3) takes the brokered
#     identity id from sub and fails ("No identifier provider for identity").
#   - Attributes, including PersonIdentifier, are only released when the authorize
#     request carries a "claims" JSON parameter. Userinfo returns {}.
# So provider_id is the custom "nia-oidc" broker (ismd-tool-backend docker/keycloak,
# image ismd-tool-keycloak): it sends niaClaims on every login and uses
# PersonIdentifier as the subject. That image must be running BEFORE provider_id is
# switched, or Keycloak rejects the unknown provider type.

locals {
  # {"id_token":{"<claim>":null,...}} — the NIA wiki format. Empty list = no claims sent.
  nia_claims_json = length(var.nia_requested_claims) == 0 ? "" : jsonencode({
    id_token = { for claim in var.nia_requested_claims : claim => null }
  })
}

resource "keycloak_oidc_identity_provider" "nia" {
  count = var.enable_nia ? 1 : 0

  realm        = keycloak_realm.ismd.id
  alias        = "nia"
  display_name = "Identita občana (NIA)"
  provider_id  = var.nia_provider_id

  authorization_url = var.nia_authorization_url
  token_url         = var.nia_token_url
  jwks_url          = var.nia_jwks_url
  user_info_url     = var.nia_user_info_url
  issuer            = var.nia_issuer

  # NIA's userinfo returns {} — calling it would overwrite the id taken from the
  # id_token with null. Everything we map comes from the id_token.
  disable_user_info = true

  # NIA end_session. Same reasoning as CAAIS: without IdP logout the národní bod
  # session survives our logout and the next login silently re-authenticates the
  # same person, with no way to switch identity. NIA uses SSO across all SePs, so
  # this matters more here, not less. Top-level attribute; rejected in extra_config.
  logout_url = var.nia_logout_url

  client_id = var.nia_client_id
  # Empty by default — NIA issues no secret (see header). Optional in provider
  # 5.7.0. If NIA ever issues one, supply via TF_VAR_nia_client_secret / Key Vault,
  # never in tfvars.
  client_secret = var.nia_client_secret

  default_scopes = var.nia_default_scopes

  # FORCE: refresh mapped attributes from NIA on every login rather than
  # importing once, so a name change at the source propagates.
  sync_mode = "FORCE"

  # backchannel_supported = false — NIA's /fpsts/oidc/endsession is a FRONT-CHANNEL
  # redirect endpoint. Keycloak defaults this to true, which makes it POST
  # server-to-server; that silently no-ops and leaves the NIA session alive.
  # false makes Keycloak redirect the browser there instead.
  #
  # store_token = false — unlike CAAIS, NIA's logout must NOT get an id_token_hint
  # (see sendIdTokenOnLogout below), so there is no reason to keep national-identity
  # tokens at rest in the Keycloak DB.
  backchannel_supported = false
  store_token           = false

  trust_email        = false
  validate_signature = var.nia_validate_signature
  hide_on_login_page = false

  extra_config = merge({
    # The only method NIA advertises. In practice only client_id goes in the body
    # that NIA reads; no secret is issued (see header).
    clientAuthMethod = var.nia_client_auth_method

    # PKCE OFF, unlike CAAIS. NIA's discovery document advertises no
    # code_challenge_methods_supported, and the developer wiki says code_verifier
    # is ignored at the token endpoint — PKCE would add nothing.
    pkceEnabled = "false"

    # Logout, verified against tnia 2026-09-18. NIA's endsession needs client_id
    # unless id_token_hint identifies the SeP, and answers ANY id_token_hint it
    # cannot read with erc=202 "Invalid OpenID Connect protocol request" - even
    # when client_id is also present. Keycloak's hint is the stored raw id_token,
    # which for NIA is the JWE, and Keycloak 24 sends no client_id by default.
    # client_id alone succeeds and returns to the registered signout URL, which is
    # Keycloak's .../broker/nia/endpoint/logout_response.
    sendClientIdOnLogout = "true"
    sendIdTokenOnLogout  = "false"
    },
    # Read by the nia-oidc broker and sent as the authorize "claims" parameter.
    local.nia_claims_json == "" ? {} : { niaClaims = local.nia_claims_json }
  )
}

# --- Claim mappers ---
#
# NIA does NOT use the standard OIDC given_name/family_name claims that caais.tf
# maps. Its claims_supported list is eIDAS-style:
#
#   CurrentGivenName, CurrentFamilyName, PersonIdentifier, DateOfBirth,
#   PlaceOfBirth, CurrentAddress, countryCodeOfBirth, age, isAgeOver, idtype,
#   idnumber, fullids, tradresaid, phonenumber, eMail
#
# Copying the CAAIS mappers verbatim would silently import nothing. Only the three
# below are mapped, matching the CAAIS attribute set; widen later with a plain
# apply (users re-login to pick up new claims).
#
# PersonIdentifier is the BSI pseudonym — the stable per-provider-group identifier
# for a citizen, and the right thing to key the local user on.
#
# Generic keycloak_custom_identity_provider_mapper, NOT the typed importer resources:
# provider 5.7.0 derives the mapper type from the IdP's provider_id, so for
# "nia-oidc" it refuses attribute importers ("identity provider is not supported yet")
# and writes an invalid "nia-oidc-username-idp-mapper" type for the username template.
# The stock OIDC mapper types work on the nia-oidc broker: Keycloak 24 applies mappers
# at login by type lookup, without a provider-compatibility filter
# (IdentityBrokerService). Config keys: claim / user.attribute (AbstractClaimMapper,
# UserAttributeMapper), template (UsernameTemplateMapper).

resource "keycloak_custom_identity_provider_mapper" "nia_first_name" {
  count = var.enable_nia ? 1 : 0

  realm                    = keycloak_realm.ismd.id
  name                     = "nia-given-name"
  identity_provider_alias  = keycloak_oidc_identity_provider.nia[0].alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"

  extra_config = {
    syncMode         = "INHERIT"
    claim            = "CurrentGivenName"
    "user.attribute" = "firstName"
  }
}

resource "keycloak_custom_identity_provider_mapper" "nia_last_name" {
  count = var.enable_nia ? 1 : 0

  realm                    = keycloak_realm.ismd.id
  name                     = "nia-family-name"
  identity_provider_alias  = keycloak_oidc_identity_provider.nia[0].alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"

  extra_config = {
    syncMode         = "INHERIT"
    claim            = "CurrentFamilyName"
    "user.attribute" = "lastName"
  }
}

resource "keycloak_custom_identity_provider_mapper" "nia_username" {
  count = var.enable_nia ? 1 : 0

  realm                    = keycloak_realm.ismd.id
  name                     = "nia-username"
  identity_provider_alias  = keycloak_oidc_identity_provider.nia[0].alias
  identity_provider_mapper = "oidc-username-idp-mapper"

  # niaUsername is added by the nia-oidc broker: PersonIdentifier with '/' replaced
  # by '-' ("CZ-CZ-<id>"). The raw value is rejected by the realm's
  # username-prohibited-characters validator, which forces the "Update Account
  # Information" page. The federated identity link keeps the raw PersonIdentifier.
  extra_config = {
    syncMode = "INHERIT"
    template = "$${CLAIM.niaUsername}"
  }
}
