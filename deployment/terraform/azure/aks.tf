resource "azurerm_kubernetes_cluster" "migration" {
  name                = local.cluster_name
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  dns_prefix          = local.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  private_cluster_enabled = var.private_cluster_enabled
  private_dns_zone_id     = var.private_cluster_enabled ? "System" : null

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # Workload ID federates the chart's service accounts to the migration identity (identity.tf).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name = "system"
    # azurerm requires a temporary pool to cycle through when vm_size and similar settings change.
    temporary_name_for_rotation = "systemtmp"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = azurerm_subnet.aks.id
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Required since azurerm 5.0; Manual keeps the autoscaling default pool without node auto-provisioning.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.node_max_count >= var.node_min_count
      error_message = "node_max_count must be greater than or equal to node_min_count."
    }

    # Authorized ranges apply only to the public API server.
    precondition {
      condition     = !var.private_cluster_enabled || length(var.api_server_authorized_ip_ranges) == 0
      error_message = "api_server_authorized_ip_ranges cannot be combined with private_cluster_enabled."
    }
  }
}

# A cluster in a subnet it did not create needs Network Contributor there to manage load
# balancers and node network interfaces.
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.migration.identity[0].principal_id
}
