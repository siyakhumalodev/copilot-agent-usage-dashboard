terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2"
    }
  }
  required_version = ">= 1.7"
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Used by Key Vault tenant_id, KV role assignments, and Grafana Admin role
data "azurerm_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ── Private Networking ───────────────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "container_apps" {
  name                 = "${var.prefix}-aca-snet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.container_apps_subnet_address_prefix]

  delegation {
    name = "Microsoft.App-environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.prefix}-pe-snet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.private_endpoints_subnet_address_prefix]
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                 = "${var.prefix}-kv-dns-link"
  private_dns_zone_id  = azurerm_private_dns_zone.key_vault.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false
}

# ── Log Analytics Workspace (required for workspace-based App Insights) ───────

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 365
}

# ── Application Insights ──────────────────────────────────────────────────────

resource "azurerm_application_insights" "ai" {
  name                = "${var.prefix}-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
}

# ── Key Vault (stores App Insights connection string) ────────────────────────

resource "azurerm_key_vault" "kv" {
  name                          = "${var.prefix}-kv"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.prefix}-kv-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.prefix}-kv-connection"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

# ARM provisions this secret without requiring public access to the vault data plane.
resource "azapi_resource" "ai_conn_str" {
  type      = "Microsoft.KeyVault/vaults/secrets@2024-11-01"
  name      = "AppInsightsConnectionString"
  parent_id = azurerm_key_vault.kv.id

  body = {
    properties = {
      attributes = {
        enabled = true
      }
      value = azurerm_application_insights.ai.connection_string
    }
  }
}

removed {
  from = azurerm_key_vault_secret.ai_conn_str

  lifecycle {
    destroy = false
  }
}

# ── Container Registry ────────────────────────────────────────────────────────

resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.prefix, "-", "")}acr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  admin_enabled       = false

  identity {
    type = "SystemAssigned"
  }
}

# ── Container App Environment ─────────────────────────────────────────────────

resource "azurerm_container_app_environment" "env" {
  name                       = "${var.prefix}-cae"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  logs_destination           = "log-analytics"
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
}

# ── User-Assigned Identity for Container App bootstrap permissions ───────────

resource "azurerm_user_assigned_identity" "collector" {
  name                = "${var.prefix}-collector-uai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# ── Container App (OTel Collector) ────────────────────────────────────────────

resource "azurerm_container_app" "collector" {
  name                         = "${var.prefix}-collector"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.collector.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.collector.id
  }

  template {
    container {
      name   = "otel-collector"
      image  = "${azurerm_container_registry.acr.login_server}/${var.image_repository}:${var.image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-conn-str"
      }
    }
  }

  secret {
    name                = "appinsights-conn-str"
    key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/AppInsightsConnectionString"
    identity            = azurerm_user_assigned_identity.collector.id
  }

  ingress {
    external_enabled = true
    # OTLP/HTTP on port 4318 — matches github.copilot.chat.otel.exporterType = "otlp-http"
    # For gRPC clients (port 4317) change transport to "http2" and target_port to 4317
    transport = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    target_port = 4318
  }

  depends_on = [
    azapi_resource.ai_conn_str,
    azurerm_private_endpoint.key_vault,
    azurerm_private_dns_zone_virtual_network_link.key_vault,
    azurerm_role_assignment.kv_secrets_user,
  ]
}

# ── AcrPull role — Container App managed identity → ACR ──────────────────────

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.collector.principal_id
}

# ── Key Vault Secrets User — Container App managed identity → Key Vault ───────

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.collector.principal_id
}

# ── Azure Managed Grafana ─────────────────────────────────────────────────────

resource "azurerm_dashboard_grafana" "grafana" {
  name                          = "${var.prefix}-grafana"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  sku                           = "Standard"
  grafana_major_version         = 12
  zone_redundancy_enabled       = false
  public_network_access_enabled = true
  api_key_enabled               = true

  identity {
    type = "SystemAssigned"
  }
}

# ── Monitoring Reader — Grafana managed identity → resource group ─────────────

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# ── Grafana Admin — grant the deploying user access to the Grafana UI ─────────

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Optional: Import dashboard JSON into Managed Grafana via Azure CLI ───────

resource "terraform_data" "grafana_dashboard_import" {
  count = var.enable_grafana_dashboard_import ? 1 : 0

  # Re-run import when dashboard file changes.
  triggers_replace = {
    dashboard_sha = filesha256(var.grafana_dashboard_definition_path)
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      az grafana dashboard import --resource-group "${azurerm_resource_group.rg.name}" --name "${azurerm_dashboard_grafana.grafana.name}" --definition "@${var.grafana_dashboard_definition_path}" --overwrite true --output none
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    EOT
  }

  depends_on = [
    azurerm_dashboard_grafana.grafana,
    azurerm_role_assignment.grafana_admin,
  ]
}
