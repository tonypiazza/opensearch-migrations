# Plan-time tests; the mock provider needs no Azure credentials.

mock_provider "azurerm" {}

variables {
  name_prefix                = "ma-dev-eastus"
  leg                        = "source"
  resource_group_name        = "ma-dev-eastus"
  local_virtual_network_name = "ma-dev-eastus-vnet"
  remote_virtual_network_id  = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/source-rg/providers/Microsoft.Network/virtualNetworks/source-vnet"
}

run "plans_our_side_of_the_peering" {
  command = plan

  assert {
    condition     = azurerm_virtual_network_peering.outbound.virtual_network_name == var.local_virtual_network_name && azurerm_virtual_network_peering.outbound.remote_virtual_network_id == var.remote_virtual_network_id
    error_message = "The peering must go from the migration virtual network to the remote one."
  }

  assert {
    condition     = azurerm_virtual_network_peering.outbound.allow_virtual_network_access == true
    error_message = "The peering must allow virtual network access."
  }
}
