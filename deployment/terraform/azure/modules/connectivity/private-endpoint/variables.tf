variable "name_prefix" {
  description = "Prefix for resource names (e.g. ma-<stage>-<location>)."
  type        = string
}

variable "leg" {
  description = "Leg label used to disambiguate resource names (source, target)."
  type        = string
}

variable "location" {
  description = "Azure region of the migration virtual network; the private endpoint must be in the same region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the private endpoint and its DNS resources."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the private endpoint's network interface is placed in."
  type        = string
}

variable "virtual_network_id" {
  description = "Migration virtual network, linked to the private DNS zone when dns_name is set."
  type        = string
}

variable "private_link_service_id" {
  description = "Resource ID of the provider's Private Link Service. Requires permission on it, and the connection is approved automatically. Set this or private_link_service_alias."
  type        = string
  default     = null
}

variable "private_link_service_alias" {
  description = "Alias of the provider's Private Link Service, for a service in another subscription or tenant. The provider must approve the connection. Set this or private_link_service_id."
  type        = string
  default     = null
}

variable "request_message" {
  description = "Message shown to the provider with a connection request made by alias."
  type        = string
  default     = null
}

variable "dns_name" {
  description = <<-EOT
    Optional FQDN to resolve to the private endpoint through a private DNS zone
    linked to the migration virtual network (e.g. myservice.example.com). When
    null, no zone is created and callers connect to the endpoint's private IP.
    Use the provider's canonical hostname so the cluster's TLS certificate validates.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.dns_name == null || length(split(".", var.dns_name)) >= 3
    error_message = "dns_name must be a host under a domain with at least 3 labels (e.g. host.example.com) so a valid parent zone can be derived."
  }
}

variable "dns_zone_domain" {
  description = "Optional private DNS zone for dns_name (e.g. example.com). When null and dns_name is set, the parent domain is derived by stripping dns_name's first label."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
