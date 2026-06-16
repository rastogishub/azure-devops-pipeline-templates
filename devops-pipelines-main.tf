# =============================================================
# Azure DevOps Pipeline Infrastructure
# Author : Shubham Rastogi
# Provisions self-hosted agents, storage, and service connections
# Based on CI/CD pipelines built at Accenture for Unilever
# =============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
  }
}

provider "azurerm" {
  features {}
}

# ------------------------------------------------------------------
# Resource Group for Pipeline Infrastructure
# ------------------------------------------------------------------
resource "azurerm_resource_group" "devops" {
  name     = "rg-devops-agents-${var.environment}-${var.location_short}"
  location = var.location
  tags     = local.common_tags
}

# ------------------------------------------------------------------
# Virtual Network for Self-Hosted Agents
# (agents need line-of-sight to internal resources)
# ------------------------------------------------------------------
resource "azurerm_virtual_network" "agents" {
  name                = "vnet-agents-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.devops.name
  location            = var.location
  address_space       = [var.agent_vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "agents" {
  name                 = "snet-pipeline-agents"
  resource_group_name  = azurerm_resource_group.devops.name
  virtual_network_name = azurerm_virtual_network.agents.name
  address_prefixes     = [var.agent_subnet_cidr]
}

# ------------------------------------------------------------------
# Azure Container Registry (store custom agent images)
# ------------------------------------------------------------------
resource "azurerm_container_registry" "agents" {
  name                = "acr${replace(var.environment, "-", "")}agents"
  resource_group_name = azurerm_resource_group.devops.name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = local.common_tags
}

# ------------------------------------------------------------------
# Self-Hosted Agent VMSS (scale-to-zero capable)
# ------------------------------------------------------------------
resource "azurerm_linux_virtual_machine_scale_set" "agents" {
  name                = "vmss-pipeline-agents-${var.environment}"
  resource_group_name = azurerm_resource_group.devops.name
  location            = var.location
  sku                 = var.agent_vm_sku
  instances           = 0   # scale-to-zero; ADO spins up on demand
  admin_username      = "azureagent"
  upgrade_mode        = "Manual"
  tags                = local.common_tags

  admin_ssh_key {
    username   = "azureagent"
    public_key = var.agent_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 128
  }

  network_interface {
    name    = "nic-agent"
    primary = true

    ip_configuration {
      name      = "ipconfig-agent"
      primary   = true
      subnet_id = azurerm_subnet.agents.id
    }
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/agent-init.sh.tpl", {
    ado_org_url        = var.ado_org_url
    ado_agent_pool     = var.ado_agent_pool_name
    ado_pat_secret_url = azurerm_key_vault_secret.ado_pat.id
  }))
}

# ------------------------------------------------------------------
# Managed Identity Role Assignments (agent needs to deploy)
# ------------------------------------------------------------------
resource "azurerm_role_assignment" "agent_contributor" {
  scope                = "/subscriptions/${var.target_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine_scale_set.agents.identity[0].principal_id
}

resource "azurerm_role_assignment" "agent_acr_pull" {
  scope                = azurerm_container_registry.agents.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine_scale_set.agents.identity[0].principal_id
}

# ------------------------------------------------------------------
# Key Vault for ADO PAT token (used by agent init script)
# ------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "devops" {
  name                       = "kv-devops-${var.environment}-${var.location_short}"
  resource_group_name        = azurerm_resource_group.devops.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  enable_rbac_authorization  = true
  tags                       = local.common_tags
}

resource "azurerm_key_vault_secret" "ado_pat" {
  name         = "ado-agent-pat"
  value        = var.ado_agent_pat
  key_vault_id = azurerm_key_vault.devops.id
  content_type = "Azure DevOps PAT"

  lifecycle {
    ignore_changes = [value]   # rotate via Key Vault, not Terraform
  }
}

# ------------------------------------------------------------------
# Storage Account for Terraform state artifacts & pipeline caches
# ------------------------------------------------------------------
resource "azurerm_storage_account" "pipeline" {
  name                     = "stpipeline${var.environment}${var.location_short}"
  resource_group_name      = azurerm_resource_group.devops.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.pipeline.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "pipeline_cache" {
  name                  = "pipeline-cache"
  storage_account_name  = azurerm_storage_account.pipeline.name
  container_access_type = "private"
}

# ------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------
locals {
  common_tags = {
    Environment = var.environment
    Service     = "AzureDevOps-Pipelines"
    ManagedBy   = "Terraform"
    Owner       = var.team_owner
    CostCenter  = var.cost_center
  }
}
