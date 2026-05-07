variable "project" {
  description = "GCP project ID"
  type = string
}

variable "region" {
  description = "GCP region"
  type = string
  default = "us-central1"
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
  description = "Kafka deployment: self-managed, confluent"
  type = string
  default = "self-managed"
}

variable "helm_chart_path" {
  description = "Path to the migration-assistant Helm chart"
  type = string
  default = "../../k8s/charts/aggregates/migrationAssistantWithArgo"
}
