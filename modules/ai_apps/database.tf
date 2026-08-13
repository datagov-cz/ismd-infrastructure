# AI service database
#
# The AI service is stateless; all persistence lives in Postgres. Rather than run
# a second Flexible Server, we create a dedicated `ismd_ai` database on the tool's
# existing server (passed in as postgres_server_id). Spring runs schema.sql on
# boot (spring.sql.init.mode=always) to create its tables.
#
# NB: this couples the AI module to the tool's Postgres server — deploy_ai_apps
# therefore requires deploy_tool_apps in the same environment. This app is the
# THIRD tenant on that server (alongside ismd_tool_db and the keycloak db); see the
# server resource in modules/tool_apps/database.tf for the shared-connection-ceiling
# and shared-admin-login caveats that apply to every tenant.
resource "azurerm_postgresql_flexible_server_database" "ai" {
  name      = var.postgres_db_name
  server_id = var.postgres_server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
