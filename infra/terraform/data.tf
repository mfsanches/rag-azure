# Storage for source documents, Key Vault for future application secrets, and a container registry.

resource "azurerm_storage_account" "this" {
  name                            = "st${local.compact_suffix}"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Entra ID only
  default_to_oauth_authentication = true
  public_network_access_enabled   = length(var.allowed_ip_addresses) > 0
  tags                            = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_addresses
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

# Created through the management plane (storage_account_id), so it works with keys disabled and no public access.
resource "azurerm_storage_container" "documents" {
  name                  = local.documents_container
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Basic SKU keeps the reference cheap; use Premium for private endpoints on the registry.
resource "azurerm_container_registry" "this" {
  name                = "cr${local.compact_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}
