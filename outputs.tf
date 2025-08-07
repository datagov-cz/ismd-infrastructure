# Outputs for the root module

# Output the container app environment details from the environment modules
output "container_app_environment_name" {
  description = "Name of the container app environment"
  value       = try(module.dev[0].container_app_environment_name, module.test[0].container_app_environment_name, module.prod[0].container_app_environment_name, "")
}

output "container_app_environment_id" {
  description = "ID of the container app environment"
  value       = try(module.dev[0].container_app_environment_id, module.test[0].container_app_environment_id, module.prod[0].container_app_environment_id, "")
}

# Output the app names for reference
output "frontend_app_name" {
  description = "Name of the frontend application"
  value       = var.frontend_app_name
}

output "backend_app_name" {
  description = "Name of the backend application"
  value       = var.backend_app_name
}
