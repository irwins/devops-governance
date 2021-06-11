# --------------
# Resource Group
# --------------

resource "azurerm_resource_group" "workspace" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = var.tags
}

# ---------------
# Storage Account
# ---------------

resource "azurerm_storage_account" "storage" {
  name                     = local.name_squished
  resource_group_name      = azurerm_resource_group.workspace.name
  location                 = azurerm_resource_group.workspace.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = false
  tags                     = var.tags
}

# ---------------
# Azure Key Vault
# ---------------

resource "azurerm_key_vault" "kv" {
  name                        = "${local.name}-kv"
  location                    = azurerm_resource_group.workspace.location
  resource_group_name         = azurerm_resource_group.workspace.name
  enabled_for_disk_encryption = true
  tenant_id                   = local.client_tenant_id
  soft_delete_retention_days  = 7     # minimum
  purge_protection_enabled    = false # so we can fully delete it
  sku_name                    = "standard"
  tags                        = var.tags
  enable_rbac_authorization   = true
}

resource "azurerm_role_assignment" "superadmins_kv_admins" {
  role_definition_name = "Key Vault Administrator" # note: takes up to 10 minutes to propagate
  principal_id         = var.superadmins_group_id
  scope                = azurerm_key_vault.kv.id
}

# ------------------
# Service Principals
# ------------------

module "workspace_sp" {
  source = "./../service-principal"
  name   = "${local.name}-sp"
}

# -----------------------
# RBAC - Role Assignments
# -----------------------

resource "azurerm_role_assignment" "team_admins" {
  role_definition_name = "Owner"
  principal_id         = var.admins_group_id
  scope                = azurerm_resource_group.workspace.id
}

# Key Vault Admin
# ---------------

# superadmins_group_id

# Contributors
# ------------

# Service Principal

# resource "azurerm_role_assignment" "workspace_sp" {
#   role_definition_name = "Contributor"
#   principal_id         = azuread_service_principal.workspace_sp.id
#   scope                = azurerm_resource_group.workspace.id
# }

# AAD Group

resource "azurerm_role_assignment" "team_devs" {
  role_definition_name = "Contributor"
  principal_id         = var.devs_group_id
  scope                = azurerm_resource_group.workspace.id
}
