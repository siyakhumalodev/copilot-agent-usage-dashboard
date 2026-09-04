output "acr_login_server" {
  description = "Container Registry login server hostname."
  value       = azurerm_container_registry.acr.login_server
}

output "container_app_fqdn" {
  description = "Public FQDN of the OTel Collector ingress; Azure dependencies remain private"
  value       = azurerm_container_app.collector.latest_revision_fqdn
}

output "key_vault_private_endpoint_ip" {
  description = "Private IP address assigned to the Key Vault private endpoint"
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "app_insights_connection_string" {
  description = "Application Insights connection string. Sensitive — do not commit to source control."
  value       = azurerm_application_insights.ai.connection_string
  sensitive   = true
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana endpoint URL."
  value       = azurerm_dashboard_grafana.grafana.endpoint
}
