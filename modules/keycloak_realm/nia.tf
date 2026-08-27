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
#   - token_endpoint_auth_methods_supported = ["client_secret_post"] ONLY. So NIA
#     is a SHARED-SECRET integration, NOT mTLS like CAAIS. No outbound keystore, no
#     init container, no certificate. Set nia_client_secret and that is the whole
#     of it. The only open question is how DIA receives that secret — the
#     registration form has no field that issues one.
#   - jwks_uri exists, so signature validation is on by default here.
#   - NO id_token_encryption_alg_values_supported → NIA does not do JWE on OIDC,
#     which is consistent with the registration form's encryption certificate
#     (field 12) being a SAML-only concern. Nothing here depends on it.
#   - NO code_challenge_methods_supported → PKCE is NOT advertised; see below.
#   - Claim names are eIDAS-style (CurrentGivenName, …), NOT the OIDC standard
#     given_name/family_name that CAAIS uses. See the mappers at the bottom.
#   - scopes_supported has NO "profile" — requesting it may be rejected.

resource "keycloak_oidc_identity_provider" "nia" {
  count = var.enable_nia ? 1 : 0

  realm        = keycloak_realm.ismd.id
  alias        = "nia"
  display_name = "Identita občana (NIA)"

  authorization_url = var.nia_authorization_url
  token_url         = var.nia_token_url
  jwks_url          = var.nia_jwks_url
  user_info_url     = var.nia_user_info_url # NIA documents none; empty = id_token claims only
  issuer            = var.nia_issuer

  # NIA end_session. Same reasoning as CAAIS: without IdP logout the národní bod
  # session survives our logout and the next login silently re-authenticates the
  # same person, with no way to switch identity. NIA uses SSO across all SePs, so
  # this matters more here, not less. Top-level attribute; rejected in extra_config.
  logout_url = var.nia_logout_url

  client_id = var.nia_client_id
  # REQUIRED when enabled — NIA supports client_secret_post only. Supply via
  # TF_VAR_nia_client_secret / Key Vault, never in tfvars.
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
  # store_token = true — required for Keycloak to send id_token_hint on logout,
  # which it can only do if it kept the brokered id_token. Costs us national-identity
  # tokens at rest in the Keycloak DB. Both settled by the CAAIS debugging.
  backchannel_supported = false
  store_token           = true

  trust_email        = false
  validate_signature = var.nia_validate_signature
  hide_on_login_page = false

  extra_config = {
    # The only method NIA advertises. Ordinary shared-secret auth in the request body.
    clientAuthMethod = var.nia_client_auth_method

    # PKCE OFF, unlike CAAIS. NIA's discovery document advertises no
    # code_challenge_methods_supported, so it is presumed unsupported — sending a
    # code_challenge risks the authorize call being rejected outright. Revisit if
    # NIA confirms support; it is a plain apply to turn on.
    pkceEnabled = "false"
  }
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

resource "keycloak_attribute_importer_identity_provider_mapper" "nia_first_name" {
  count = var.enable_nia ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "nia-given-name"
  identity_provider_alias = keycloak_oidc_identity_provider.nia[0].alias
  claim_name              = "CurrentGivenName"
  user_attribute          = "firstName"

  extra_config = {
    syncMode = "INHERIT"
  }
}

resource "keycloak_attribute_importer_identity_provider_mapper" "nia_last_name" {
  count = var.enable_nia ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "nia-family-name"
  identity_provider_alias = keycloak_oidc_identity_provider.nia[0].alias
  claim_name              = "CurrentFamilyName"
  user_attribute          = "lastName"

  extra_config = {
    syncMode = "INHERIT"
  }
}

resource "keycloak_user_template_importer_identity_provider_mapper" "nia_username" {
  count = var.enable_nia ? 1 : 0

  realm                   = keycloak_realm.ismd.id
  name                    = "nia-username"
  identity_provider_alias = keycloak_oidc_identity_provider.nia[0].alias
  template                = "$${CLAIM.PersonIdentifier}"

  extra_config = {
    syncMode = "INHERIT"
  }
}
