output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "api_url" {
  value = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "api_app_name" {
  value = azurerm_container_app.api.name
}

output "ingest_job_name" {
  value = azurerm_container_app_job.ingest.name
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "registry_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "search_endpoint" {
  value = "https://${azurerm_search_service.this.name}.search.windows.net"
}
