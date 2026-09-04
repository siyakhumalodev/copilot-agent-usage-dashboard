variable "prefix" {
  description = "Short prefix applied to all resource names. Use lowercase letters and hyphens only."
  type        = string
  default     = "copilot-dash"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Name of the resource group to create."
  type        = string
  default     = "copilot-dashboard-rg"
}

variable "subscription_id" {
  description = "Azure subscription ID used by the azurerm provider."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the private workload virtual network"
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_apps_subnet_address_prefix" {
  description = "Address prefix for the delegated Container Apps infrastructure subnet"
  type        = string
  default     = "10.20.0.0/23"
}

variable "private_endpoints_subnet_address_prefix" {
  description = "Address prefix for private endpoints"
  type        = string
  default     = "10.20.2.0/24"
}

variable "image_repository" {
  description = "Container image repository name in ACR."
  type        = string
  default     = "otel-collector"
}

variable "image_tag" {
  description = "Container image tag to deploy. Use immutable tags in CI/CD (for example, git SHA)."
  type        = string
  default     = "latest"
}

variable "enable_grafana_dashboard_import" {
  description = "If true, Terraform imports the dashboard JSON into Managed Grafana using Azure CLI."
  type        = bool
  default     = false
}

variable "grafana_dashboard_definition_path" {
  description = "Path to the Grafana dashboard JSON file, relative to terraform/ directory."
  type        = string
  default     = "../grafana-agent-usage-geo.json"
}
