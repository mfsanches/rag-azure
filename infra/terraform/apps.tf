# Container Apps environment inside the virtual network, the RAG API and the ingestion job.

locals {
  shared_env = {
    AZURE_OPENAI_ENDPOINT                 = azurerm_cognitive_account.openai.endpoint
    CHAT_SMALL_DEPLOYMENT                 = azurerm_cognitive_deployment.chat_small.name
    CHAT_LARGE_DEPLOYMENT                 = azurerm_cognitive_deployment.chat_large.name
    EMBEDDING_DEPLOYMENT                  = azurerm_cognitive_deployment.embedding.name
    EMBEDDING_DIMENSIONS                  = tostring(var.embedding_dimensions)
    AZURE_SEARCH_ENDPOINT                 = "https://${azurerm_search_service.this.name}.search.windows.net"
    SEARCH_INDEX_NAME                     = local.search_index_name
    STORAGE_ACCOUNT_URL                   = azurerm_storage_account.this.primary_blob_endpoint
    DOCUMENTS_CONTAINER                   = local.documents_container
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${local.suffix}"
  location                       = azurerm_resource_group.this.location
  resource_group_name            = azurerm_resource_group.this.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id       = azurerm_subnet.apps.id
  internal_load_balancer_enabled = false
  tags                           = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  # Apps start only after their access and network paths exist.
  depends_on = [azurerm_private_endpoint.this]
}

resource "azurerm_container_app" "api" {
  name                         = "ca-api-${local.suffix}"
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  dynamic "registry" {
    for_each = var.use_created_registry ? [1] : []
    content {
      server   = azurerm_container_registry.this.login_server
      identity = azurerm_user_assigned_identity.api.id
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 5

    container {
      name   = "api"
      image  = var.container_image
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = merge(local.shared_env, { AZURE_CLIENT_ID = azurerm_user_assigned_identity.api.client_id })
        content {
          name  = env.key
          value = env.value
        }
      }

      liveness_probe {
        transport        = "HTTP"
        path             = "/healthz"
        port             = 8000
        initial_delay    = 10
        interval_seconds = 30
      }
    }

    http_scale_rule {
      name                = "http"
      concurrent_requests = "20"
    }
  }

  depends_on = [
    azurerm_role_assignment.openai,
    azurerm_role_assignment.search,
    azurerm_role_assignment.registry,
  ]
}

resource "azurerm_container_app_job" "ingest" {
  name                         = "caj-ingest-${local.suffix}"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 3600
  replica_retry_limit          = 1
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ingest.id]
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  dynamic "registry" {
    for_each = var.use_created_registry ? [1] : []
    content {
      server   = azurerm_container_registry.this.login_server
      identity = azurerm_user_assigned_identity.ingest.id
    }
  }

  template {
    container {
      name    = "ingest"
      image   = var.container_image
      command = ["python", "ingest.py"]
      cpu     = 0.5
      memory  = "1Gi"

      dynamic "env" {
        for_each = merge(local.shared_env, { AZURE_CLIENT_ID = azurerm_user_assigned_identity.ingest.client_id })
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.openai,
    azurerm_role_assignment.search,
    azurerm_role_assignment.storage,
    azurerm_role_assignment.registry,
  ]
}
