variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "leg" {
  description = "Leg label (source, target)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the migration virtual network."
  type        = string
}

variable "local_virtual_network_name" {
  description = "Name of the migration virtual network."
  type        = string
}

variable "remote_virtual_network_id" {
  description = "Full resource ID of the virtual network to peer with, including its subscription."
  type        = string
}
