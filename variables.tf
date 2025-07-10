variable "environment" {
  description = "The environment (dev, test, prod)"
  type        = string
}

variable "environment_prefix" {
  description = "Short prefix for the environment (e.g., 'ismd' for 'ismd-dev')"
  type        = string
  default     = "ismd"
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
  default     = "ismd-validator-dev"
}
