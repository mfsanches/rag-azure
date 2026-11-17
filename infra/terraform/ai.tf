# Azure OpenAI (chat + embeddings) and Azure AI Search. Both private, both Entra ID only.

resource "azurerm_cognitive_account" "openai" {
  name                          = "oai-${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "oai-${local.suffix}"
  public_network_access_enabled = false
  local_auth_enabled            = false # no API keys
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
  }
}

# The service rejects parallel deployment changes, so chain them: each waits for the previous one.
resource "azurerm_cognitive_deployment" "chat_small" {
  name                 = var.chat_small_deployment
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.model_deployments[var.chat_small_deployment].model
    version = var.model_deployments[var.chat_small_deployment].version
  }

  sku {
    name     = var.model_deployments[var.chat_small_deployment].sku_name
    capacity = var.model_deployments[var.chat_small_deployment].capacity
  }
}

resource "azurerm_cognitive_deployment" "chat_large" {
  name                 = var.chat_large_deployment
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.model_deployments[var.chat_large_deployment].model
    version = var.model_deployments[var.chat_large_deployment].version
  }

  sku {
    name     = var.model_deployments[var.chat_large_deployment].sku_name
    capacity = var.model_deployments[var.chat_large_deployment].capacity
  }

  depends_on = [azurerm_cognitive_deployment.chat_small]
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_deployment
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.model_deployments[var.embedding_deployment].model
    version = var.model_deployments[var.embedding_deployment].version
  }

  sku {
    name     = var.model_deployments[var.embedding_deployment].sku_name
    capacity = var.model_deployments[var.embedding_deployment].capacity
  }

  depends_on = [azurerm_cognitive_deployment.chat_large]
}

resource "azurerm_search_service" "this" {
  name                          = "srch-${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  sku                           = var.search_sku
  replica_count                 = 1
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false # no admin or query keys
  semantic_search_sku           = "free"
  tags                          = var.tags
}
