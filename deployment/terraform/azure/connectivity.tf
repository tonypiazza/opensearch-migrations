# Optional per-leg private connectivity to the source and target clusters.
# Both legs default to mode = "none" (no resources, no change to a public-path
# deployment). See source_connectivity / target_connectivity in variables.tf.
#
# Operator responsibilities not automated here (kept minimal by design):
#   - private_endpoint: a connection by alias stays Pending until the provider approves it;
#     source_/target_private_endpoint_status reports it. Use the provider's canonical
#     hostname for dns_name so the cluster's TLS certificate validates.
#   - vnet_peering: the remote owner must create the peering back to this virtual network
#     (virtual_network_id output). Remote ranges must not overlap vnet_cidr or the pod
#     range, and the remote must allow aks_subnet_cidr, since pod traffic leaves from node IPs.

locals {
  private_endpoint_subnet_enabled = anytrue([
    var.source_connectivity.mode == "private_endpoint",
    var.target_connectivity.mode == "private_endpoint",
    var.storage_connectivity.mode == "private_endpoint",
  ])
}

resource "azurerm_subnet" "private_endpoints" {
  count = local.private_endpoint_subnet_enabled ? 1 : 0

  name                 = "${local.name}-pe"
  resource_group_name  = azurerm_resource_group.migration.name
  virtual_network_name = azurerm_virtual_network.migration.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]
}

module "source_connectivity_private_endpoint" {
  count  = var.source_connectivity.mode == "private_endpoint" ? 1 : 0
  source = "./modules/connectivity/private-endpoint"

  name_prefix                = local.name
  leg                        = "source"
  location                   = azurerm_resource_group.migration.location
  resource_group_name        = azurerm_resource_group.migration.name
  subnet_id                  = azurerm_subnet.private_endpoints[0].id
  virtual_network_id         = azurerm_virtual_network.migration.id
  private_link_service_id    = var.source_connectivity.private_link_service_id
  private_link_service_alias = var.source_connectivity.private_link_service_alias
  request_message            = var.source_connectivity.request_message
  dns_name                   = var.source_connectivity.dns_name
  dns_zone_domain            = var.source_connectivity.dns_zone_domain
  tags                       = local.common_tags
}

module "target_connectivity_private_endpoint" {
  count  = var.target_connectivity.mode == "private_endpoint" ? 1 : 0
  source = "./modules/connectivity/private-endpoint"

  name_prefix                = local.name
  leg                        = "target"
  location                   = azurerm_resource_group.migration.location
  resource_group_name        = azurerm_resource_group.migration.name
  subnet_id                  = azurerm_subnet.private_endpoints[0].id
  virtual_network_id         = azurerm_virtual_network.migration.id
  private_link_service_id    = var.target_connectivity.private_link_service_id
  private_link_service_alias = var.target_connectivity.private_link_service_alias
  request_message            = var.target_connectivity.request_message
  dns_name                   = var.target_connectivity.dns_name
  dns_zone_domain            = var.target_connectivity.dns_zone_domain
  tags                       = local.common_tags
}

module "source_connectivity_peering" {
  count  = var.source_connectivity.mode == "vnet_peering" ? 1 : 0
  source = "./modules/connectivity/vnet-peering"

  name_prefix                = local.name
  leg                        = "source"
  resource_group_name        = azurerm_resource_group.migration.name
  local_virtual_network_name = azurerm_virtual_network.migration.name
  remote_virtual_network_id  = var.source_connectivity.remote_virtual_network_id
}

module "target_connectivity_peering" {
  count  = var.target_connectivity.mode == "vnet_peering" ? 1 : 0
  source = "./modules/connectivity/vnet-peering"

  name_prefix                = local.name
  leg                        = "target"
  resource_group_name        = azurerm_resource_group.migration.name
  local_virtual_network_name = azurerm_virtual_network.migration.name
  remote_virtual_network_id  = var.target_connectivity.remote_virtual_network_id

  # Azure rejects concurrent peering changes on one virtual network.
  depends_on = [module.source_connectivity_peering]
}
