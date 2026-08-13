module "ismd_realm" {
  source = "../modules/keycloak_realm"

  realm_name         = "ismd"
  realm_display_name = "ismd"

  login_with_email_allowed = true
  registration_allowed     = var.registration_allowed
  reset_password_allowed   = var.reset_password_allowed
  verify_email             = var.verify_email

  ismd_app_root_url                  = var.app_base_url
  ismd_app_valid_redirect_uris       = ["${var.app_base_url}/*"]
  ismd_app_web_origins               = [var.app_origin]
  ismd_app_post_logout_redirect_uris = ["${var.app_base_url}/*"]

  # DEV-only local dev-loop origins (empty on TEST/PROD via tfvars).
  additional_redirect_uris             = [for o in var.local_dev_origins : "${o}/*"]
  additional_web_origins               = var.local_dev_origins
  additional_post_logout_redirect_uris = [for o in var.local_dev_origins : "${o}/*"]

  sso_session_idle_timeout = var.sso_session_idle_timeout
  sso_session_max_lifespan = var.sso_session_max_lifespan

  smtp_enabled  = var.smtp_enabled
  smtp_from     = var.smtp_from
  smtp_username = var.smtp_username
  smtp_password = var.smtp_password

  # CAAIS brokered login. URLs are pre-filled per env in tfvars; enable_caais
  # stays false until the client_id is issued and the container-side mTLS
  # keystore is live.
  enable_caais            = var.enable_caais
  caais_client_id         = var.caais_client_id
  caais_authorization_url = var.caais_authorization_url
  caais_token_url         = var.caais_token_url
  caais_jwks_url          = var.caais_jwks_url
  caais_user_info_url     = var.caais_user_info_url
  caais_issuer            = var.caais_issuer
  caais_logout_url        = var.caais_logout_url
}

output "ismd_realm_id" {
  value = module.ismd_realm.realm_id
}
