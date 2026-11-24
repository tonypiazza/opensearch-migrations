# We create only our side. The remote owner must create the peering from their virtual network
# back to ours; until both sides exist the peering stays Initiated and carries no traffic.
resource "azurerm_virtual_network_peering" "outbound" {
  name                         = "${var.name_prefix}-peer-${var.leg}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = var.local_virtual_network_name
  remote_virtual_network_id    = var.remote_virtual_network_id
  allow_virtual_network_access = true
}
