output "endpoint_id" {
  description = "ID of the private endpoint."
  value       = azurerm_private_endpoint.remote.id
}

output "private_ip" {
  description = "Private IP of the endpoint in the migration virtual network. Assigned even while the connection is pending approval. Known only after apply."
  value       = azurerm_private_endpoint.remote.private_service_connection[0].private_ip_address
}

output "connection_status" {
  description = "Connection status. 'Pending' means the provider must approve the connection before it carries traffic; 'Approved' means ready."
  value       = azurerm_private_endpoint.remote.private_service_connection[0].status
}

output "endpoint_fqdn" {
  description = "The FQDN that resolves to the endpoint through the private DNS zone; null when dns_name is unset (use private_ip instead). Put this (or private_ip) in the workflow target/source cluster endpoint config."
  value       = var.dns_name
}
