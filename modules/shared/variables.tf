variable "environment" {
  description = "The environment name (e.g., dev, test, prod)"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to create"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
}
