variable "location" {
  description = "The Azure region where all resources in this example should be created."
  type        = string
}

variable "environment" {
  description = "The environment name (e.g., dev, test, prod)"
  type        = string
}

variable "container_app_environment_name" {
  description = "The name of the Container Apps Environment (e.g., 'whiteforest-fdd5cbd0')"
  type        = string
  default     = "whiteforest-fdd5cbd0"
}

variable "container_app_environment_id" {
  description = "The ID of the Container Apps Environment"
  type        = string
  default     = ""
}
