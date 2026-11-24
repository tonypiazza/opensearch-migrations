locals {
  dns_enabled = var.dns_name != null
  # Zone domain: explicit override, else parent of dns_name (strip first label).
  zone_domain = var.dns_zone_domain != null ? var.dns_zone_domain : (
    local.dns_enabled ? join(".", slice(split(".", var.dns_name), 1, length(split(".", var.dns_name)))) : null
  )
  record_name = local.dns_enabled ? (var.dns_name == local.zone_domain ? "@" : trimsuffix(var.dns_name, ".${local.zone_domain}")) : null

  manual_connection = var.private_link_service_alias != null
}

resource "azurerm_private_endpoint" "remote" {
  name                = "${var.name_prefix}-pe-${var.leg}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  # A Private Link Service has no sub-resources, so subresource_names is omitted.
  private_service_connection {
    name                              = "${var.name_prefix}-pe-${var.leg}"
    private_connection_resource_id    = var.private_link_service_id
    private_connection_resource_alias = var.private_link_service_alias
    is_manual_connection              = local.manual_connection
    request_message                   = local.manual_connection ? var.request_message : null
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = (var.private_link_service_id == null) != (var.private_link_service_alias == null)
      error_message = "Set exactly one of private_link_service_id or private_link_service_alias."
    }
  }
}

# Azure has no standard private DNS zone for a customer's Private Link Service, so the
# record for dns_name is managed here rather than through a private DNS zone group.
resource "azurerm_private_dns_zone" "remote" {
  count = local.dns_enabled ? 1 : 0

  name                = local.zone_domain
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = var.dns_name == local.zone_domain || endswith(var.dns_name, ".${local.zone_domain}")
      error_message = "dns_name must be inside dns_zone_domain."
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "remote" {
  count = local.dns_enabled ? 1 : 0

  name                 = "${var.name_prefix}-pe-${var.leg}"
  private_dns_zone_id  = azurerm_private_dns_zone.remote[0].id
  virtual_network_id   = var.virtual_network_id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_dns_a_record" "remote" {
  count = local.dns_enabled ? 1 : 0

  name                = local.record_name
  private_dns_zone_id = azurerm_private_dns_zone.remote[0].id
  ttl                 = 60
  records             = [azurerm_private_endpoint.remote.private_service_connection[0].private_ip_address]
  tags                = var.tags
}
