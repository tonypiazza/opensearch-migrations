# Plan-time tests; the mock provider needs no Azure credentials.

mock_provider "azurerm" {
  # azurerm parses resource IDs at plan time, so the random mock defaults fail; supply valid ones.
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/privateDnsZones/example.com"
    }
  }
}

variables {
  name_prefix             = "ma-dev-eastus"
  leg                     = "target"
  location                = "eastus"
  resource_group_name     = "ma-dev-eastus"
  subnet_id               = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/virtualNetworks/ma-dev-eastus-vnet/subnets/ma-dev-eastus-pe"
  virtual_network_id      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/ma-dev-eastus/providers/Microsoft.Network/virtualNetworks/ma-dev-eastus-vnet"
  private_link_service_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/provider-rg/providers/Microsoft.Network/privateLinkServices/search-pls"
}

run "connects_by_id_without_dns_by_default" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.remote.private_service_connection[0].private_connection_resource_id == var.private_link_service_id
    error_message = "The endpoint must connect to private_link_service_id."
  }

  assert {
    condition     = azurerm_private_endpoint.remote.private_service_connection[0].is_manual_connection == false
    error_message = "A connection by resource ID is approved automatically."
  }

  assert {
    condition     = length(azurerm_private_dns_zone.remote) == 0 && length(azurerm_private_dns_a_record.remote) == 0
    error_message = "No DNS resources are created without dns_name."
  }

  assert {
    condition     = output.endpoint_fqdn == null
    error_message = "endpoint_fqdn must be null without dns_name."
  }
}

run "connects_by_alias_with_manual_approval" {
  command = plan

  variables {
    private_link_service_id    = null
    private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
    request_message            = "Migration Assistant target connection"
  }

  assert {
    condition     = azurerm_private_endpoint.remote.private_service_connection[0].is_manual_connection == true
    error_message = "A connection by alias must request manual approval."
  }

  assert {
    condition     = azurerm_private_endpoint.remote.private_service_connection[0].request_message == "Migration Assistant target connection"
    error_message = "The request message must be sent with a connection by alias."
  }
}

run "dns_name_creates_a_linked_zone_and_record" {
  command = plan

  variables {
    dns_name = "search.example.com"
  }

  assert {
    condition     = azurerm_private_dns_zone.remote[0].name == "example.com"
    error_message = "The zone must be dns_name's parent domain."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.remote[0].virtual_network_id == var.virtual_network_id && azurerm_private_dns_zone_virtual_network_link.remote[0].registration_enabled == false
    error_message = "The zone must be linked to the migration virtual network without auto-registration."
  }

  assert {
    condition     = azurerm_private_dns_a_record.remote[0].name == "search"
    error_message = "The A record must be dns_name relative to the zone."
  }

  assert {
    condition     = output.endpoint_fqdn == "search.example.com"
    error_message = "endpoint_fqdn must echo dns_name."
  }
}

run "zone_named_for_the_host_uses_an_apex_record" {
  command = plan

  variables {
    dns_name        = "search.example.com"
    dns_zone_domain = "search.example.com"
  }

  assert {
    condition     = azurerm_private_dns_zone.remote[0].name == "search.example.com" && azurerm_private_dns_a_record.remote[0].name == "@"
    error_message = "A zone named for the host must hold an apex record."
  }
}

run "rejects_both_id_and_alias" {
  command = plan

  variables {
    private_link_service_alias = "search-pls.11111111-1111-1111-1111-111111111111.eastus.azure.privatelinkservice"
  }

  expect_failures = [
    azurerm_private_endpoint.remote,
  ]
}

run "rejects_neither_id_nor_alias" {
  command = plan

  variables {
    private_link_service_id = null
  }

  expect_failures = [
    azurerm_private_endpoint.remote,
  ]
}

run "rejects_dns_name_outside_the_zone" {
  command = plan

  variables {
    dns_name        = "search.example.com"
    dns_zone_domain = "example.org"
  }

  expect_failures = [
    azurerm_private_dns_zone.remote,
  ]
}
