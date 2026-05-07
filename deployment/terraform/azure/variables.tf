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
  description = "Source cluster endpoint URL"
  type = string
}

variable "target_endpoint" {
  description = "Target cluster endpoint URL"
  type = string
}

variable "kafka_type" {
  description = "Kafka deployment: self-managed, event-hubs"
  type = string
  default = "self-managed"
}

variable "helm_chart_path" {
  description = "Path to the migration-assistant Helm chart"
  type = string
  default = "../../k8s/charts/aggregates/migrationAssistantWithArgo"
}
