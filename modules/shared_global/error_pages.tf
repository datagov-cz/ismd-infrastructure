# Storage Account for App Gateway custom error pages.
# Static website hosting serves the HTML at a public HTTPS URL that the
# App Gateway custom_error_configuration blocks can reference.

resource "azurerm_storage_account" "error_pages" {
  name                     = "ismdstaticerrorpages"
  resource_group_name      = azurerm_resource_group.shared_global.name
  location                 = azurerm_resource_group.shared_global.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "App Gateway error pages"
  }
}

# The static_website block on azurerm_storage_account was deprecated in favor of
# this separate resource (azurerm provider v4.x; removed entirely in v5.0).
# Behavior is identical: serves index_document at the static-web endpoint and
# uses error_404_document as the fallback for missing paths.
resource "azurerm_storage_account_static_website" "error_pages" {
  storage_account_id = azurerm_storage_account.error_pages.id
  index_document     = "502.html"
  error_404_document = "502.html"
}

resource "azurerm_storage_blob" "error_502" {
  name                 = "502.html"
  storage_container_id = "${azurerm_storage_account.error_pages.primary_blob_endpoint}$web"
  type                 = "Block"
  content_type         = "text/html"
  source               = "${path.module}/../../static-pages/502.html"
  content_md5          = filemd5("${path.module}/../../static-pages/502.html")
}

resource "azurerm_storage_blob" "error_403" {
  name                 = "403.html"
  storage_container_id = "${azurerm_storage_account.error_pages.primary_blob_endpoint}$web"
  type                 = "Block"
  content_type         = "text/html"
  source               = "${path.module}/../../static-pages/403.html"
  content_md5          = filemd5("${path.module}/../../static-pages/403.html")
}
