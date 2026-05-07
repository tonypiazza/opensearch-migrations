# This module is a placeholder. Cloud-specific implementations
# should configure the kubernetes and helm providers appropriately
# for their environment (GKE workload identity, AKS managed identity, etc.)

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type = string
  default = ""
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  type = string
  default = ""
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate"
  type = string
  default = ""
}

variable "token" {
  description = "Authentication token"
  type = string
  default = ""
}
