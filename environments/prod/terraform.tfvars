# Production environment variables
environment = "prod"
location = "germanywestcentral"

# Shared module variables
shared_resource_group_name = "ismd-shared-prod"

# Validator module variables
validator_resource_group_name = "ismd-validator-prod"
frontend_image = "ghcr.io/datagov-cz/ismd-validator-frontend:latest"
backend_image = "ghcr.io/datagov-cz/ismd-validator-backend/ismd-backend-validator:latest"
