terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

variable "helm_chart_path" {
  description = "Path to the migration-assistant Helm chart"
  type = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type = string
  default = "migration"
}

variable "release_name" {
  description = "Helm release name"
  type = string
  default = "migration-assistant"
}

variable "values_yaml" {
  description = "Additional Helm values (YAML string)"
  type = string
  default = ""
}

variable "cloud_provider" {
  description = "Cloud provider: aws, gcp, azure"
  type = string
}

variable "source_endpoint" {
  description = "Source Elasticsearch/OpenSearch endpoint"
  type = string
}

variable "target_endpoint" {
  description = "Target OpenSearch endpoint"
  type = string
}

resource "helm_release" "migration_assistant" {
  name       = var.release_name
  namespace  = var.namespace
  chart      = var.helm_chart_path
  create_namespace = true

  values = [
    var.values_yaml,
    yamlencode({
      cloudProvider = var.cloud_provider
      sourceEndpoint = var.source_endpoint
      targetEndpoint = var.target_endpoint
    })
  ]
}

output "release_name" {
  value = helm_release.migration_assistant.name
}

output "namespace" {
  value = helm_release.migration_assistant.namespace
}
