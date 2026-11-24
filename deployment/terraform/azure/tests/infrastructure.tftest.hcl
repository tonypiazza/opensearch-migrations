# Plan-time tests for the Azure deployment.
# Mock providers keep the tests local: no Azure credentials or cloud resources are required.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  mock_data "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/existing-rg/providers/Microsoft.Storage/storageAccounts/existingaccount"
    }
  }

  # azurerm parses resource IDs at plan time, so the random mock defaults fail; supply valid ones.
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/virtualNetworks/ma-dev-eastus-vnet"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/virtualNetworks/ma-dev-eastus-vnet/subnets/ma-dev-eastus-aks"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/privateDnsZones/example.com"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Storage/storageAccounts/madevabcdef"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ma-dev-eastus-migration"
      client_id    = "33333333-3333-3333-3333-333333333333"
      principal_id = "44444444-4444-4444-4444-444444444444"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.ContainerService/managedClusters/migration-aks-cluster-dev-eastus"
      oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/11111111-1111-1111-1111-111111111111/55555555-5555-5555-5555-555555555555/"
      identity        = { principal_id = "66666666-6666-6666-6666-666666666666" }
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.OperationalInsights/workspaces/ma-dev-eastus-logs"
    }
  }

  mock_resource "azurerm_monitor_data_collection_endpoint" {
    defaults = {
      id                      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Insights/dataCollectionEndpoints/ma-dev-eastus-logs"
      logs_ingestion_endpoint = "https://ma-dev-eastus-logs-wxyz.eastus-1.ingest.monitor.azure.com"
    }
  }

  mock_resource "azurerm_monitor_private_link_scope" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Insights/privateLinkScopes/ma-dev-eastus-logs"
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id                      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Insights/dataCollectionRules/ma-dev-eastus-logs"
      logs_ingestion_endpoint = "https://ma-dev-eastus-logs-abcd-eastus.logs.z1.ingest.monitor.azure.com"
      immutable_id            = "dcr-00000000000000000000000000000000"
    }
  }
}

mock_provider "azuread" {
  mock_resource "azuread_application_registration" {
    defaults = {
      id        = "/applications/88888888-8888-8888-8888-888888888888"
      client_id = "99999999-9999-9999-9999-999999999999"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "77777777-7777-7777-7777-777777777777"
    }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  location = "eastus"
  stage    = "dev"
}

run "cluster_enables_workload_identity" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.migration.oidc_issuer_enabled && azurerm_kubernetes_cluster.migration.workload_identity_enabled
    error_message = "The AKS cluster must enable the OIDC issuer and Workload ID."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.migration.network_profile[0].network_plugin == "azure" && azurerm_kubernetes_cluster.migration.network_profile[0].network_plugin_mode == "overlay"
    error_message = "The AKS cluster must use Azure CNI overlay."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.migration.default_node_pool[0].vm_size == "Standard_D4s_v5"
    error_message = "The node pool must default to Standard_D4s_v5."
  }
}

run "federated_credentials_cover_the_chart_service_accounts" {
  command = plan

  assert {
    condition = toset([for c in azurerm_federated_identity_credential.migration : c.subject]) == toset([
      "system:serviceaccount:ma:migrations-service-account",
      "system:serviceaccount:ma:argo-workflow-executor",
      "system:serviceaccount:ma:argo-test-workflow-executor",
      "system:serviceaccount:ma:migration-console-access-role",
      "system:serviceaccount:ma:argo-server",
    ])
    error_message = "Federated credentials must cover every service account the chart annotates for Workload ID."
  }

  assert {
    condition     = alltrue([for c in azurerm_federated_identity_credential.migration : length(c.audience) == 1 && contains(c.audience, "api://AzureADTokenExchange")])
    error_message = "Federated credentials must use the Workload ID token audience."
  }
}

run "storage_account_and_container_created_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.migration) == 1 && length(azurerm_storage_container.migration) == 1
    error_message = "The storage account and container must be created by default."
  }

  assert {
    condition     = azurerm_role_assignment.migration_blob_data.role_definition_name == "Storage Blob Data Contributor"
    error_message = "The workload identity must have Storage Blob Data Contributor on the storage account."
  }
}

run "existing_storage_account_is_used_without_creating_one" {
  command = plan

  variables {
    create_storage_account                       = false
    existing_storage_account_name                = "existingaccount"
    existing_storage_account_resource_group_name = "existing-rg"
    deploy_helm                                  = true
    migration_assistant_version                  = "3.4.2"
  }

  assert {
    condition     = length(azurerm_storage_account.migration) == 0 && length(azurerm_storage_container.migration) == 0
    error_message = "An existing storage account must not be created or given a Terraform-managed container."
  }

  assert {
    condition     = anytrue([for s in helm_release.migration_assistant[0].set : s.name == "azureStorageConfiguration.create" && s.value == "true"])
    error_message = "With an existing storage account, the chart must create the container if it is missing."
  }
}

run "existing_storage_account_requires_its_name" {
  command = plan

  variables {
    create_storage_account = false
  }

  expect_failures = [data.azurerm_storage_account.existing]
}

run "helm_requires_an_image_version" {
  command = plan

  variables {
    deploy_helm = true
  }

  expect_failures = [helm_release.migration_assistant[0]]
}

run "helm_passes_identity_and_storage_to_the_chart" {
  command = plan

  variables {
    deploy_helm                 = true
    migration_assistant_version = "3.4.2"
  }

  assert {
    condition     = length(helm_release.migration_assistant[0].values) == 1 && helm_release.migration_assistant[0].create_namespace
    error_message = "Without Azure Monitor, the release must use only valuesAks.yaml and create its namespace."
  }

  assert {
    condition = alltrue([
      for name in ["azure.workloadIdentityClientId", "azureStorageConfiguration.accountName", "azureStorageConfiguration.containerName"] :
      anytrue([for s in helm_release.migration_assistant[0].set : s.name == name])
    ])
    error_message = "The release must receive the workload identity client ID and the storage account and container."
  }

  assert {
    condition     = anytrue([for s in helm_release.migration_assistant[0].set : s.name == "azureStorageConfiguration.create" && s.value == "false"])
    error_message = "The chart must not create the container Terraform owns."
  }

  assert {
    condition     = !anytrue([for s in helm_release.migration_assistant[0].set : startswith(s.name, "azure.monitor.")])
    error_message = "Without Azure Monitor, no azure.monitor values may be set."
  }
}

run "azure_monitor_logs_off_by_default" {
  command = plan

  assert {
    condition = (
      length(azurerm_log_analytics_workspace.migration) == 0 &&
      length(azurerm_monitor_data_collection_rule.migration) == 0 &&
      length(azuread_application_registration.monitor) == 0 &&
      length(kubernetes_secret_v1.monitor) == 0
    )
    error_message = "Azure Monitor resources must not be created unless enable_azure_monitor_logs is true."
  }
}

run "azure_monitor_logs_use_a_direct_rule_and_the_chart_secret" {
  command = plan

  variables {
    enable_azure_monitor_logs   = true
    deploy_helm                 = true
    migration_assistant_version = "3.4.2"
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.migration[0].kind == "Direct" && azurerm_monitor_data_collection_rule.migration[0].data_collection_endpoint_id == null
    error_message = "The data collection rule must be Direct, with its own ingestion endpoint and no data collection endpoint."
  }

  assert {
    condition     = azurerm_log_analytics_workspace_table_custom_log.migration[0].name == "MigrationAssistant_CL"
    error_message = "The custom table must be MigrationAssistant_CL."
  }

  assert {
    condition     = azurerm_role_assignment.monitor_publisher[0].role_definition_name == "Monitoring Metrics Publisher"
    error_message = "The Entra application must be able to publish to the data collection rule."
  }

  assert {
    condition     = kubernetes_secret_v1.monitor[0].metadata[0].name == "azure-monitor-logs-credentials" && contains(keys(kubernetes_secret_v1.monitor[0].data), "clientSecret")
    error_message = "The client secret must be in the azure-monitor-logs-credentials Secret under clientSecret, where valuesAksMonitor.yaml reads it."
  }

  assert {
    condition     = length(helm_release.migration_assistant[0].values) == 2 && !helm_release.migration_assistant[0].create_namespace
    error_message = "With Azure Monitor, the release must add valuesAksMonitor.yaml and use the namespace Terraform created for the Secret."
  }

  assert {
    condition = alltrue([
      for name in ["azure.monitor.tenantId", "azure.monitor.clientId", "azure.monitor.dceUrl", "azure.monitor.dcrImmutableId", "azure.monitor.tableName"] :
      anytrue([for s in helm_release.migration_assistant[0].set : s.name == name])
    ])
    error_message = "The release must receive every azure.monitor value that azure-metadata requires."
  }
}

# Azure rejects tag names containing < > % & \ ? / at apply time, which a plan does not catch.
run "tag_names_avoid_azure_reserved_characters" {
  command = plan

  variables {
    tags = { CostCenter = "migrations" }
  }

  assert {
    condition     = alltrue([for k in keys(azurerm_resource_group.migration.tags) : !can(regex("[<>%&\\\\?/]", k))])
    error_message = "Tag names must not contain the characters Azure reserves: < > % & \\ ? /"
  }

  assert {
    condition     = azurerm_resource_group.migration.tags["Stage"] == "dev" && azurerm_resource_group.migration.tags["CostCenter"] == "migrations"
    error_message = "Resources must carry the Stage tag and the caller's tags."
  }
}

run "stage_rejects_invalid_names" {
  command = plan

  variables {
    stage = "Dev_1"
  }

  expect_failures = [var.stage]
}

run "node_max_count_must_cover_min_count" {
  command = plan

  variables {
    node_min_count = 4
    node_max_count = 2
  }

  expect_failures = [azurerm_kubernetes_cluster.migration]
}

run "connectivity_defaults_to_none_no_resources" {
  command = plan

  assert {
    condition     = length(module.source_connectivity_private_endpoint) == 0 && length(module.target_connectivity_private_endpoint) == 0
    error_message = "No private endpoints are created by default."
  }

  assert {
    condition     = length(module.source_connectivity_peering) == 0 && length(module.target_connectivity_peering) == 0
    error_message = "No peerings are created by default."
  }

  assert {
    condition     = length(azurerm_subnet.private_endpoints) == 0
    error_message = "The private endpoint subnet is created only when a private endpoint is configured."
  }

  assert {
    condition     = output.source_private_endpoint == null && output.target_private_endpoint == null && output.source_private_endpoint_status == null && output.target_private_endpoint_status == null
    error_message = "Private endpoint outputs must be null by default."
  }
}

run "rejects_invalid_source_mode" {
  command = plan

  variables {
    source_connectivity = { mode = "carrier_pigeon" }
  }

  expect_failures = [var.source_connectivity]
}

run "rejects_invalid_target_mode" {
  command = plan

  variables {
    target_connectivity = { mode = "privatelink" }
  }

  expect_failures = [var.target_connectivity]
}

run "private_endpoint_requires_a_service_id_or_alias" {
  command = plan

  variables {
    target_connectivity = { mode = "private_endpoint" }
  }

  expect_failures = [var.target_connectivity]
}

run "private_endpoint_rejects_both_id_and_alias" {
  command = plan

  variables {
    source_connectivity = {
      mode                       = "private_endpoint"
      private_link_service_id    = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/provider-rg/providers/Microsoft.Network/privateLinkServices/search-pls"
      private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
    }
  }

  expect_failures = [var.source_connectivity]
}

run "vnet_peering_requires_the_remote_network" {
  command = plan

  variables {
    source_connectivity = { mode = "vnet_peering" }
  }

  expect_failures = [var.source_connectivity]
}

run "target_private_endpoint_plans_endpoint_subnet_and_dns" {
  command = plan

  variables {
    target_connectivity = {
      mode                       = "private_endpoint"
      private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
      dns_name                   = "search.example.com"
    }
  }

  assert {
    condition     = length(module.target_connectivity_private_endpoint) == 1 && length(module.source_connectivity_private_endpoint) == 0
    error_message = "Only the target leg gets a private endpoint."
  }

  assert {
    condition     = azurerm_subnet.private_endpoints[0].address_prefixes == tolist(["10.212.16.0/27"])
    error_message = "The private endpoint subnet must use private_endpoint_subnet_cidr."
  }

  assert {
    condition     = module.target_connectivity_private_endpoint[0].endpoint_fqdn == "search.example.com"
    error_message = "The target endpoint must resolve through dns_name."
  }

  assert {
    condition     = output.target_private_endpoint == "search.example.com"
    error_message = "target_private_endpoint must be the dns_name when one is set."
  }
}

run "source_vnet_peering_plans_our_side_only" {
  command = plan

  variables {
    source_connectivity = {
      mode                      = "vnet_peering"
      remote_virtual_network_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/source-rg/providers/Microsoft.Network/virtualNetworks/source-vnet"
    }
  }

  assert {
    condition     = length(module.source_connectivity_peering) == 1 && length(module.target_connectivity_peering) == 0
    error_message = "Only the source leg gets a peering."
  }

  assert {
    condition     = length(azurerm_subnet.private_endpoints) == 0
    error_message = "Peering does not need the private endpoint subnet."
  }

  assert {
    condition     = output.source_private_endpoint == null
    error_message = "source_private_endpoint is null for vnet_peering."
  }
}

run "pod_cidr_is_passed_to_the_cluster" {
  command = plan

  variables {
    pod_cidr = "10.250.0.0/16"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.migration.network_profile[0].pod_cidr == "10.250.0.0/16"
    error_message = "pod_cidr must set the cluster's overlay pod range."
  }
}

run "storage_private_endpoint_off_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.blob) == 0 && length(azurerm_private_dns_zone.blob) == 0
    error_message = "No Blob private endpoint or zone is created by default."
  }

  assert {
    condition     = azurerm_storage_account.migration[0].public_network_access == "Enabled"
    error_message = "The storage account keeps public access by default."
  }

  assert {
    condition     = output.storage_private_endpoint_ip == null
    error_message = "storage_private_endpoint_ip must be null by default."
  }
}

run "storage_private_endpoint_plans_blob_endpoint_zone_and_link" {
  command = plan

  variables {
    storage_connectivity = { mode = "private_endpoint" }
  }

  assert {
    condition     = azurerm_private_endpoint.blob[0].private_service_connection[0].subresource_names == tolist(["blob"])
    error_message = "The private endpoint must target the account's blob sub-resource."
  }

  assert {
    condition     = azurerm_private_dns_zone.blob[0].name == "privatelink.blob.core.windows.net"
    error_message = "The Blob private DNS zone must be privatelink.blob.core.windows.net."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.blob[0].resolution_policy == "NxDomainRedirect"
    error_message = "The zone link must fall back to public DNS so accounts without a private endpoint still resolve."
  }

  assert {
    condition     = length(azurerm_subnet.private_endpoints) == 1
    error_message = "The Blob private endpoint needs the private endpoint subnet."
  }

  assert {
    condition     = azurerm_storage_account.migration[0].public_network_access == "Enabled"
    error_message = "A private endpoint alone does not turn off public access."
  }
}

run "storage_disable_public_access_turns_off_the_public_endpoint" {
  command = plan

  variables {
    storage_connectivity = { mode = "private_endpoint", disable_public_access = true }
  }

  assert {
    condition     = azurerm_storage_account.migration[0].public_network_access == "Disabled"
    error_message = "disable_public_access must set public_network_access to Disabled."
  }
}

run "storage_disable_public_access_requires_a_private_endpoint" {
  command = plan

  variables {
    storage_connectivity = { disable_public_access = true }
  }

  expect_failures = [var.storage_connectivity]
}

run "storage_rejects_invalid_mode" {
  command = plan

  variables {
    storage_connectivity = { mode = "service_endpoint" }
  }

  expect_failures = [var.storage_connectivity]
}

run "storage_private_endpoint_on_an_existing_account" {
  command = plan

  variables {
    create_storage_account                       = false
    existing_storage_account_name                = "existingaccount"
    existing_storage_account_resource_group_name = "existing-rg"
    storage_connectivity                         = { mode = "private_endpoint" }
  }

  assert {
    condition     = azurerm_private_endpoint.blob[0].private_service_connection[0].private_connection_resource_id == "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/existing-rg/providers/Microsoft.Storage/storageAccounts/existingaccount"
    error_message = "The private endpoint must target the existing account."
  }
}

run "storage_disable_public_access_rejects_an_existing_account" {
  command = plan

  variables {
    create_storage_account                       = false
    existing_storage_account_name                = "existingaccount"
    existing_storage_account_resource_group_name = "existing-rg"
    storage_connectivity                         = { mode = "private_endpoint", disable_public_access = true }
  }

  expect_failures = [azurerm_private_endpoint.blob]
}

run "control_plane_public_and_unrestricted_by_default" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.migration.private_cluster_enabled == false
    error_message = "The API server must stay public by default."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.migration.api_server_access_profile) == 0
    error_message = "The API server must not restrict addresses by default."
  }
}

run "authorized_ip_ranges_restrict_the_public_api_server" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10/32", "198.51.100.0/24"]
  }

  assert {
    condition     = toset(azurerm_kubernetes_cluster.migration.api_server_access_profile[0].authorized_ip_ranges) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "api_server_authorized_ip_ranges must restrict the API server."
  }
}

run "authorized_ip_ranges_reject_invalid_cidrs" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "private_cluster_uses_an_aks_managed_dns_zone" {
  command = plan

  variables {
    private_cluster_enabled = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.migration.private_cluster_enabled == true && azurerm_kubernetes_cluster.migration.private_dns_zone_id == "System"
    error_message = "A private cluster must use an AKS-managed private DNS zone."
  }
}

run "private_cluster_rejects_authorized_ip_ranges" {
  command = plan

  variables {
    private_cluster_enabled         = true
    api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  }

  expect_failures = [azurerm_kubernetes_cluster.migration]
}

run "monitor_private_link_off_by_default" {
  command = plan

  variables {
    enable_azure_monitor_logs = true
  }

  assert {
    condition     = length(azurerm_monitor_private_link_scope.migration) == 0 && length(azurerm_monitor_data_collection_endpoint.migration) == 0 && length(azurerm_private_endpoint.monitor) == 0
    error_message = "Azure Monitor Private Link is off by default."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.migration[0].data_collection_endpoint_id == null
    error_message = "The rule uses its own ingestion endpoint without Private Link."
  }

  assert {
    condition     = length(azurerm_subnet.private_endpoints) == 0 && length(azurerm_private_dns_zone.blob) == 0
    error_message = "Logs without Private Link need no private endpoint subnet or Blob zone."
  }
}

run "monitor_private_link_requires_azure_monitor_logs" {
  command = plan

  variables {
    azure_monitor_private_link = true
  }

  expect_failures = [azurerm_monitor_private_link_scope.migration]
}

run "monitor_private_link_plans_endpoint_scope_and_private_endpoint" {
  command = plan

  variables {
    enable_azure_monitor_logs  = true
    azure_monitor_private_link = true
  }

  assert {
    condition     = azurerm_monitor_data_collection_endpoint.migration[0].public_network_access_enabled == false
    error_message = "The data collection endpoint must not accept public traffic."
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.migration[0].ingestion_access_mode == "PrivateOnly" && azurerm_monitor_private_link_scope.migration[0].query_access_mode == "Open"
    error_message = "The scope must take ingestion only over Private Link and leave queries open."
  }

  assert {
    condition     = length(azurerm_monitor_private_link_scoped_service.workspace) == 1 && length(azurerm_monitor_private_link_scoped_service.endpoint) == 1
    error_message = "The workspace and the data collection endpoint must both be in the scope."
  }

  assert {
    condition     = azurerm_private_endpoint.monitor[0].private_service_connection[0].subresource_names == tolist(["azuremonitor"])
    error_message = "The private endpoint must target the scope's azuremonitor sub-resource."
  }

  assert {
    condition = toset(keys(azurerm_private_dns_zone.monitor)) == toset([
      "privatelink.monitor.azure.com",
      "privatelink.oms.opinsights.azure.com",
      "privatelink.ods.opinsights.azure.com",
      "privatelink.agentsvc.azure-automation.net",
    ]) && length(azurerm_private_dns_zone_virtual_network_link.monitor) == 4
    error_message = "The Azure Monitor private DNS zones must be created and linked."
  }

  assert {
    condition     = length(azurerm_private_dns_zone.blob) == 1 && length(azurerm_subnet.private_endpoints) == 1
    error_message = "Azure Monitor Private Link needs the shared Blob zone and the private endpoint subnet."
  }

  assert {
    condition     = length(azurerm_private_endpoint.blob) == 0
    error_message = "Azure Monitor Private Link must not add a storage account private endpoint."
  }
}

# Apply against the mock providers: HashiCorp Terraform leaves computed mock values unknown at plan.
run "monitor_private_link_sends_logs_to_the_data_collection_endpoint" {
  command = apply

  variables {
    enable_azure_monitor_logs  = true
    azure_monitor_private_link = true
  }

  assert {
    condition     = output.logs_ingestion_endpoint == "https://ma-dev-eastus-logs-wxyz.eastus-1.ingest.monitor.azure.com"
    error_message = "logs_ingestion_endpoint must be the data collection endpoint's with Private Link."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.migration[0].data_collection_endpoint_id == "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Insights/dataCollectionEndpoints/ma-dev-eastus-logs"
    error_message = "The rule must use the data collection endpoint."
  }
}
