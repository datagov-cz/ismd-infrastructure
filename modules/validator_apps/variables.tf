variable "frontend_app_name" {
  description = "Name of the frontend container app"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Name of the backend container app"
  type        = string
  default     = "ismd-validator-backend"
}

variable "workload_profile_name" {
  description = "Name of the workload profile to use for the container apps"
  type        = string
  default     = "Consumption"
}

variable "workload_profile_type" {
  description = "Type of the workload profile (e.g., 'Consumption', 'D4')"
  type        = string
  default     = "Consumption"
}
