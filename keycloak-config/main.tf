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

  smtp_enabled  = var.smtp_enabled
  smtp_from     = var.smtp_from
  smtp_username = var.smtp_username
  smtp_password = var.smtp_password
}

output "ismd_realm_id" {
  value = module.ismd_realm.realm_id
}
