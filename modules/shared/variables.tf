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

variable "vnet_address_space" {
  description = "IPv4 address space for the VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vnet_address_space_ipv6" {
  description = "IPv6 address space for the VNet"
  type        = string
  default     = "fd00:db8:deca::/48"
}

variable "validator_subnet_address_prefix" {
  description = "Address prefix for the validator subnet (/23 minimum for Container Apps)"
  type        = string
  default     = "10.0.2.0/23"
}

variable "tool_subnet_address_prefix" {
  description = "Address prefix for the tool subnet (/23 minimum for Container Apps)"
  type        = string
  default     = "10.0.4.0/23"
}

variable "workload_profile_type" {
  description = "Workload profile type for the shared Container App Environment"
  type        = string
  default     = "D4"
}

variable "workload_profile_min_count" {
  description = "Minimum number of instances for the workload profile"
  type        = number
  default     = 1
}

variable "workload_profile_max_count" {
  description = "Maximum number of instances for the workload profile"
  type        = number
  default     = 3
}
