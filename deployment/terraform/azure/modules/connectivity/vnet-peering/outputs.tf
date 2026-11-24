output "peering_id" {
  description = "ID of our side of the peering."
  value       = azurerm_virtual_network_peering.outbound.id
}

output "remote_virtual_network_id" {
  description = "The peered virtual network."
  value       = var.remote_virtual_network_id
}
