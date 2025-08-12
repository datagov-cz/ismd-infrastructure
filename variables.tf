variable "environment" {
  description = "The environment (dev, test, prod)"
  type        = string
}


variable "location" {
  description = "The Azure region to deploy to"
  type        = string
  default     = "germanywestcentral"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend-dev"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image"
  type        = string
  default     = "latest"
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend-dev"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image"
  type        = string
  default     = "latest"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-tfstate"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
}

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
  default     = "" # Will be populated from ARM_SUBSCRIPTION_ID environment variable if not specified
}

variable "container_app_environment_domain" {
  description = "The default domain for container apps in the environment"
  type        = string
  default     = "yellowforest-c02e8fbc.germanywestcentral.azurecontainerapps.io"
}

variable "frontend_app_name" {
  description = "Base name of the frontend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Base name of the backend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-backend"
}
