resource "azurerm_storage_account" "migration" {
  count = var.create_storage_account ? 1 : 0

  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.migration.name
  location                 = azurerm_resource_group.migration.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false
  public_network_access           = var.storage_connectivity.disable_public_access ? "Disabled" : "Enabled"

  tags = local.common_tags
}

resource "azurerm_storage_container" "migration" {
  count = var.create_storage_account ? 1 : 0

  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.migration[0].id
  container_access_type = "private"
}

locals {
  # Azure Monitor Private Link also maps a storage endpoint in this zone.
  blob_private_dns_zone_enabled = var.storage_connectivity.mode == "private_endpoint" || local.monitor_private_link
}

# The account's own blob hostname resolves to the private endpoint through this zone. Unresolved
# names fall back to public DNS, so other accounts without a private endpoint, such as a source
# cluster's snapshot account, stay reachable.
resource "azurerm_private_dns_zone" "blob" {
  count = local.blob_private_dns_zone_enabled ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.migration.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count = local.blob_private_dns_zone_enabled ? 1 : 0

  name                 = "${local.name}-blob"
  private_dns_zone_id  = azurerm_private_dns_zone.blob[0].id
  virtual_network_id   = azurerm_virtual_network.migration.id
  registration_enabled = false
  resolution_policy    = "NxDomainRedirect"
  tags                 = local.common_tags
}

resource "azurerm_private_endpoint" "blob" {
  count = var.storage_connectivity.mode == "private_endpoint" ? 1 : 0

  name                = "${local.name}-pe-blob"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${local.name}-pe-blob"
    private_connection_resource_id = local.storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.create_storage_account || !var.storage_connectivity.disable_public_access
      error_message = "storage_connectivity.disable_public_access applies only to a storage account this module creates; turn off public access on an existing account yourself."
    }
  }
}
