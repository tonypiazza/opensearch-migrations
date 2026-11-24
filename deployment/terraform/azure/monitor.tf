locals {
  monitor_table_name  = "MigrationAssistant_CL"
  monitor_stream_name = "Custom-${local.monitor_table_name}"

  # The fields the chart's fluent-bit pipeline puts on every record (valuesAksMonitor.yaml).
  monitor_string_columns = ["log", "level", "namespace", "pod", "container", "workflow"]

  monitor_private_link = var.enable_azure_monitor_logs && var.azure_monitor_private_link
  monitor_logs_ingestion_endpoint = !var.enable_azure_monitor_logs ? null : (
    local.monitor_private_link
    ? azurerm_monitor_data_collection_endpoint.migration[0].logs_ingestion_endpoint
    : azurerm_monitor_data_collection_rule.migration[0].logs_ingestion_endpoint
  )

  # Zones the Azure Monitor private endpoint maps besides privatelink.blob.core.windows.net (storage.tf).
  monitor_private_dns_zones = toset([
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
  ])
}

resource "azurerm_log_analytics_workspace" "migration" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name                = "${local.name}-logs-${random_string.suffix.result}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

resource "azurerm_log_analytics_workspace_table_custom_log" "migration" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name         = local.monitor_table_name
  workspace_id = azurerm_log_analytics_workspace.migration[0].id

  column {
    name = "TimeGenerated"
    type = "dateTime"
  }

  dynamic "column" {
    for_each = local.monitor_string_columns
    content {
      name = column.value
      type = "string"
    }
  }
}

# A Direct rule has its own logs ingestion endpoint, so a data collection endpoint is needed
# only to reach the workspace over Private Link.
resource "azurerm_monitor_data_collection_rule" "migration" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name                        = "${local.name}-logs"
  location                    = azurerm_resource_group.migration.location
  resource_group_name         = azurerm_resource_group.migration.name
  kind                        = "Direct"
  data_collection_endpoint_id = local.monitor_private_link ? azurerm_monitor_data_collection_endpoint.migration[0].id : null

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.migration[0].id
      name                  = "workspace"
    }
  }

  stream_declaration {
    stream_name = local.monitor_stream_name

    column {
      name = "TimeGenerated"
      type = "datetime"
    }

    dynamic "column" {
      for_each = local.monitor_string_columns
      content {
        name = column.value
        type = "string"
      }
    }
  }

  data_flow {
    streams       = [local.monitor_stream_name]
    destinations  = ["workspace"]
    output_stream = local.monitor_stream_name
    transform_kql = "source"
  }

  tags = local.common_tags

  depends_on = [azurerm_log_analytics_workspace_table_custom_log.migration]
}

# fluent-bit's azure_logs_ingestion output authenticates only with a client secret; it has no
# managed identity or Workload ID option.
resource "azuread_application_registration" "monitor" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  display_name = "${local.name}-logs"
}

resource "azuread_service_principal" "monitor" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  client_id = azuread_application_registration.monitor[0].client_id
}

resource "azuread_application_password" "monitor" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  application_id = azuread_application_registration.monitor[0].id
  display_name   = "fluent-bit"
}

resource "azurerm_role_assignment" "monitor_publisher" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  scope                = azurerm_monitor_data_collection_rule.migration[0].id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azuread_service_principal.monitor[0].object_id
}

# The chart does not create this Secret, and fluent-bit pods cannot start without it, so it
# must exist before the release.
resource "kubernetes_namespace_v1" "migration" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "monitor" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  metadata {
    name      = "azure-monitor-logs-credentials"
    namespace = kubernetes_namespace_v1.migration[0].metadata[0].name
  }

  data = {
    clientSecret = azuread_application_password.monitor[0].value
  }
}

resource "azurerm_monitor_data_collection_endpoint" "migration" {
  count = local.monitor_private_link ? 1 : 0

  name                          = "${local.name}-logs"
  location                      = azurerm_resource_group.migration.location
  resource_group_name           = azurerm_resource_group.migration.name
  public_network_access_enabled = false
  tags                          = local.common_tags
}

resource "azurerm_monitor_private_link_scope" "migration" {
  count = var.azure_monitor_private_link ? 1 : 0

  name                  = "${local.name}-logs"
  resource_group_name   = azurerm_resource_group.migration.name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "Open"
  tags                  = local.common_tags

  lifecycle {
    precondition {
      condition     = var.enable_azure_monitor_logs
      error_message = "azure_monitor_private_link requires enable_azure_monitor_logs."
    }
  }
}

resource "azurerm_monitor_private_link_scoped_service" "workspace" {
  count = local.monitor_private_link ? 1 : 0

  name                = "${local.name}-logs-workspace"
  resource_group_name = azurerm_resource_group.migration.name
  scope_name          = azurerm_monitor_private_link_scope.migration[0].name
  linked_resource_id  = azurerm_log_analytics_workspace.migration[0].id
}

resource "azurerm_monitor_private_link_scoped_service" "endpoint" {
  count = local.monitor_private_link ? 1 : 0

  name                = "${local.name}-logs-endpoint"
  resource_group_name = azurerm_resource_group.migration.name
  scope_name          = azurerm_monitor_private_link_scope.migration[0].name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.migration[0].id
}

resource "azurerm_private_dns_zone" "monitor" {
  for_each = local.monitor_private_link ? local.monitor_private_dns_zones : toset([])

  name                = each.value
  resource_group_name = azurerm_resource_group.migration.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  for_each = azurerm_private_dns_zone.monitor

  name                 = "${local.name}-monitor"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = azurerm_virtual_network.migration.id
  registration_enabled = false
  tags                 = local.common_tags
}

resource "azurerm_private_endpoint" "monitor" {
  count = local.monitor_private_link ? 1 : 0

  name                = "${local.name}-pe-monitor"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${local.name}-pe-monitor"
    private_connection_resource_id = azurerm_monitor_private_link_scope.migration[0].id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "azuremonitor"
    private_dns_zone_ids = concat([for zone in azurerm_private_dns_zone.monitor : zone.id], [azurerm_private_dns_zone.blob[0].id])
  }

  tags = local.common_tags

  # DNS records are created for the resources already in the scope.
  depends_on = [
    azurerm_monitor_private_link_scoped_service.workspace,
    azurerm_monitor_private_link_scoped_service.endpoint,
  ]
}
