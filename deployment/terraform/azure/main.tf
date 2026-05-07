terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type = string
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type = string
}

variable "location" {
  description = "Azure region"
  type = string
  default = "East US"
}

variable "source_endpoint" {
  description = "Source ES/OS endpoint"
  type = string
}

variable "target_endpoint" {
  description = "Target OS endpoint"
  type = string
}

resource "azurerm_resource_group" "migration" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "migration" {
  name                = "migration-cluster-${var.resource_group_name}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  dns_prefix          = "migration"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_D4s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }
}

resource "azurerm_virtual_network" "migration_vnet" {
  name                = "migration-vnet-${var.resource_group_name}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name
  address_space       = ["10.0.0.0/16"]

  subnet {
    name           = "migration-subnet"
    address_prefix = "10.0.1.0/24"
  }
}

resource "azurerm_network_security_group" "migration_nsg" {
  name                = "migration-nsg-${var.resource_group_name}"
  location            = azurerm_resource_group.migration.location
  resource_group_name = azurerm_resource_group.migration.name

  security_rule {
    name                       = "allow-migration-api"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "9200", "9300"]
    source_address_prefixes    = ["*"]
    destination_address_prefix = "*"
  }
}

resource "azurerm_storage_account" "migration" {
  name                     = "migrationsnapshots${replace(var.resource_group_name, "-", "")}"
  resource_group_name      = azurerm_resource_group.migration.name
  location                 = azurerm_resource_group.migration.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "migration_snapshots" {
  name                  = "migration-snapshots"
  storage_account_name  = azurerm_storage_account.migration.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "aks_storage_access" {
  scope                = azurerm_storage_account.migration.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.migration.kubelet_identity[0].object_id
}

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
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.migration.name} --name ${azurerm_kubernetes_cluster.migration.name}"
}
