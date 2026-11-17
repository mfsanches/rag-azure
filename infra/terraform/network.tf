resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# Container Apps environment (workload profiles need a delegated /27 or larger).
resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 7, 0)] # /23

  delegation {
    name = "containerapps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [cidrsubnet(var.vnet_address_space, 8, 2)] # /24
  private_endpoint_network_policies = "Enabled"
}

locals {
  dns_zones = {
    openai = "privatelink.openai.azure.com"
    search = "privatelink.search.windows.net"
    blob   = "privatelink.blob.core.windows.net"
    vault  = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = local.dns_zones
  name                  = "link-${azurerm_virtual_network.this.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# Data services are reachable only from inside the network.
locals {
  private_endpoints = {
    oai  = { target = azurerm_cognitive_account.openai.id, subresource = "account", zone = "openai" }
    srch = { target = azurerm_search_service.this.id, subresource = "searchService", zone = "search" }
    blob = { target = azurerm_storage_account.this.id, subresource = "blob", zone = "blob" }
    kv   = { target = azurerm_key_vault.this.id, subresource = "vault", zone = "vault" }
  }
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.private_endpoints
  name                = "pe-${each.key}-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "pe-${each.key}-${local.suffix}"
    private_connection_resource_id = each.value.target
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.value.zone].id]
  }
}
