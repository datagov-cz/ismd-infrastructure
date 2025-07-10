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

variable "backend_address_pools" {
  description = "List of backend address pool configurations"
  type = list(object({
    name         = string
    fqdns        = optional(list(string))
    ip_addresses = optional(list(string))
  }))
  default = []
}

variable "backend_http_settings" {
  description = "List of backend HTTP settings configurations"
  type = list(object({
    name                                = string
    cookie_based_affinity               = optional(string, "Disabled")
    port                                = number
    protocol                            = optional(string, "Http")
    request_timeout                     = optional(number, 60)
    probe_name                          = optional(string)
    pick_host_name_from_backend_address = optional(bool, false)
  }))
  default = []
}

variable "probes" {
  description = "List of health probe configurations"
  type = list(object({
    name                = string
    protocol            = string
    path                = string
    host                = optional(string)
    interval            = optional(number, 30)
    timeout             = optional(number, 30)
    unhealthy_threshold = optional(number, 3)
    match = optional(list(object({
      status_code = list(string)
    })), [])
  }))
  default = []
}

variable "http_listeners" {
  description = "List of HTTP listener configurations"
  type = list(object({
    name                           = string
    frontend_ip_configuration_name = string
    frontend_port_name             = string
    protocol                       = string
    host_name                      = optional(string)
  }))
  default = []
}

variable "request_routing_rules" {
  description = "List of request routing rule configurations"
  type = list(object({
    name                        = string
    rule_type                   = string
    http_listener_name          = string
    backend_address_pool_name   = optional(string)
    backend_http_settings_name  = optional(string)
    url_path_map_name           = optional(string)
    priority                    = optional(number)
  }))
  default = []
}

variable "url_path_maps" {
  description = "List of URL path map configurations"
  type = list(object({
    name                               = string
    default_backend_address_pool_name  = optional(string)
    default_backend_http_settings_name = optional(string)
    path_rules = optional(list(object({
      name                       = string
      paths                      = list(string)
      backend_address_pool_name  = optional(string)
      backend_http_settings_name = optional(string)
    })))
  }))
  default = []
}
