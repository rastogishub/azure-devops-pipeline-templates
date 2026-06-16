# =============================================================
# Azure DevOps Pipeline Infrastructure - Variables
# =============================================================

variable "environment" {
  description = "Deployment environment: dev | uat | prod"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  description = "Short region code"
  type        = string
  default     = "eus"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
}

variable "team_owner" {
  description = "Team responsible for pipeline infrastructure"
  type        = string
  default     = "DevOps-Platform-Team"
}

# Networking
variable "agent_vnet_cidr" {
  description = "CIDR for agent VNet"
  type        = string
  default     = "10.20.0.0/16"
}

variable "agent_subnet_cidr" {
  description = "CIDR for agent subnet"
  type        = string
  default     = "10.20.1.0/24"
}

# Agent VMSS
variable "agent_vm_sku" {
  description = "VM SKU for pipeline agents"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "agent_ssh_public_key" {
  description = "SSH public key for agent VMs"
  type        = string
  sensitive   = true
}

# Azure DevOps
variable "ado_org_url" {
  description = "Azure DevOps organisation URL (e.g. https://dev.azure.com/myorg)"
  type        = string
}

variable "ado_agent_pool_name" {
  description = "Name of the self-hosted agent pool in Azure DevOps"
  type        = string
  default     = "SelfHosted-Linux-Agents"
}

variable "ado_agent_pat" {
  description = "Azure DevOps PAT for agent registration (stored in Key Vault)"
  type        = string
  sensitive   = true
}

# Subscriptions
variable "target_subscription_id" {
  description = "Subscription where the agent VMSS will deploy resources"
  type        = string
  sensitive   = true
}
