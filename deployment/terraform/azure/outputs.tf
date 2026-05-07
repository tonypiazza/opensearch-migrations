output "cluster_name" {
  value = azurerm_kubernetes_cluster.migration.name
}

output "cluster_endpoint" {
  value = azurerm_kubernetes_cluster.migration.kube_config.0.host
}

output "container_name" {
  value = azurerm_storage_container.migration_snapshots.name
}

output "storage_account_name" {
  value = azurerm_storage_account.migration.name
}

output "kubeconfig_command" {
  description = "Run this to get kubectl access"
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.migration.name}"
}
