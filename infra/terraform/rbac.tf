# Least-privilege role assignments. The API can only read; the ingestion job can write the index.

locals {
  api_principal    = azurerm_user_assigned_identity.api.principal_id
  ingest_principal = azurerm_user_assigned_identity.ingest.principal_id

  openai_roles = {
    api    = { principal = local.api_principal, role = "Cognitive Services OpenAI User" }
    ingest = { principal = local.ingest_principal, role = "Cognitive Services OpenAI User" }
  }

  search_roles = {
    api_read       = { principal = local.api_principal, role = "Search Index Data Reader" }
    ingest_write   = { principal = local.ingest_principal, role = "Search Index Data Contributor" }
    ingest_service = { principal = local.ingest_principal, role = "Search Service Contributor" } # create the index
  }

  storage_roles = merge(
    { ingest_read = { principal = local.ingest_principal, role = "Storage Blob Data Reader" } },
    var.grant_deployer_upload ? {
      deployer_upload = { principal = data.azurerm_client_config.current.object_id, role = "Storage Blob Data Contributor" }
    } : {}
  )

  registry_roles = {
    api    = { principal = local.api_principal, role = "AcrPull" }
    ingest = { principal = local.ingest_principal, role = "AcrPull" }
  }
}

resource "azurerm_role_assignment" "openai" {
  for_each             = local.openai_roles
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search" {
  for_each             = local.search_roles
  scope                = azurerm_search_service.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "storage" {
  for_each             = local.storage_roles
  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
}

resource "azurerm_role_assignment" "registry" {
  for_each             = local.registry_roles
  scope                = azurerm_container_registry.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
}
