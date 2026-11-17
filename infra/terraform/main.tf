data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  suffix              = "${var.name_prefix}-${random_string.suffix.result}"
  compact_suffix      = replace(local.suffix, "-", "")
  search_index_name   = "docs"
  documents_container = "documents"
}

resource "azurerm_resource_group" "this" {
  name     = coalesce(var.resource_group_name, "rg-${local.suffix}")
  location = var.location
  tags     = var.tags
}

# ---------- Monitoring ----------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

# ---------- Identities: one per workload, so each gets only the access it needs ----------

resource "azurerm_user_assigned_identity" "api" {
  name                = "id-api-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "ingest" {
  name                = "id-ingest-${local.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}
