# Test Environment — VNet peering to shared global network

# VNet Peering from this environment's VNet to the shared global VNet
resource "azurerm_virtual_network_peering" "env_to_shared" {
  count                        = var.shared_global_vnet_id != "" ? 1 : 0
  name                         = "peer-${var.environment}-to-global"
  resource_group_name          = var.shared_resource_group_name
  virtual_network_name         = module.shared.virtual_network_name
  remote_virtual_network_id    = var.shared_global_vnet_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false
  use_remote_gateways          = false # Set to false since there's no gateway in the global VNet
}

# VNet Peering from the shared global VNet back to this environment's VNet
resource "azurerm_virtual_network_peering" "shared_to_env" {
  count                        = var.shared_global_vnet_name != "" ? 1 : 0
  name                         = "peer-global-to-${var.environment}"
  resource_group_name          = var.shared_global_resource_group_name
  virtual_network_name         = var.shared_global_vnet_name
  remote_virtual_network_id    = module.shared.virtual_network_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false # Set to false since there's no gateway in the global VNet
  use_remote_gateways          = false
}
