data "azurerm_client_config" "current" {}

# Suffix
# ------
# Some Azure resources, e.g. storage accounts must have globally
# unique names. Use a suffix to avoid automation errors.

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result

  # Default to current ARM client
  superadmins_aad_object_id = var.superadmins_aad_object_id == "" ? data.azurerm_client_config.current.object_id : var.superadmins_aad_object_id
}


# Azure AD Groups
# ---------------

resource "azuread_group" "groups" {
  for_each                = var.groups
  display_name            = "demo-${each.value}-${local.suffix}"
  prevent_duplicate_names = true
}


# Azure DevOps
# ------------

resource "azuredevops_project" "team_projects" {
  for_each        = var.projects
  name            = each.value.name
  description     = each.value.description
  visibility      = "private"
  version_control = "Git"

  features = {
    repositories = "enabled"
    pipelines    = "enabled"
    artifacts    = "disabled"
    boards       = "disabled"
    testplans    = "disabled"
  }
}

module "ado_standard_permissions" {
  for_each       = var.projects
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.team_projects["proj_${each.value.team}"].id
  team_aad_id    = azuread_group.groups["${each.value.team}_devs"].id
  admin_aad_id   = azuread_group.groups["${each.value.team}_admins"].id

  depends_on = [
    azuread_group.groups
  ]
}

# Supermarket Project

resource "azuredevops_project" "supermarket" {
  name            = "supermarket"
  description     = "Example: 1 project, many teams, many repos"
  visibility      = "private"
  version_control = "Git"

  features = {
    boards       = "enabled"
    repositories = "enabled"
    pipelines    = "enabled"
    artifacts    = "disabled"
    testplans    = "disabled"
  }
}

# TODO: supermarket collab model with devs, admins and all
module "supermarket_permissions_fruits" {
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.supermarket.id
  team_aad_id    = azuread_group.groups["fruits_devs"].id
  admin_aad_id   = azuread_group.groups["fruits_admins"].id

  depends_on = [
    azuread_group.groups
  ]
}

module "supermarket_permissions_veggies" {
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.supermarket.id
  team_aad_id    = azuread_group.groups["veggies_devs"].id
  admin_aad_id   = azuread_group.groups["veggies_admins"].id

  depends_on = [
    azuread_group.groups
  ]
}

# Shared Collaboration

resource "azuredevops_project" "collaboration" {
  name            = "shared-collaboration"
  description     = "Example: what if separate teams should talk to each other? (Disadvantage: cannot link external project commits to work items in this project)"
  visibility      = "private"
  version_control = "Git"

  features = {
    boards       = "enabled"
    repositories = "disabled"
    pipelines    = "disabled"
    artifacts    = "disabled"
    testplans    = "disabled"
  }
}

module "collaboration_permissions_fruits" {
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.collaboration.id
  team_aad_id    = azuread_group.groups["fruits_devs"].id
  admin_aad_id   = azuread_group.groups["fruits_admins"].id

  depends_on = [
    azuread_group.groups
  ]
}

module "collaboration_permissions_veggies" {
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.collaboration.id
  team_aad_id    = azuread_group.groups["veggies_devs"].id
  admin_aad_id   = azuread_group.groups["veggies_admins"].id

  depends_on = [
    azuread_group.groups
  ]
}


# Workspaces
# ----------

module "arm_environments" {
  for_each             = var.environments
  source               = "./modules/azure-resources"
  name                 = "${each.value.team}-${each.value.env}-${local.suffix}"
  team_group_id        = azuread_group.groups["${each.value.team}_devs"].id
  admin_group_id       = azuread_group.groups["${each.value.team}_admins"].id
  superadmins_group_id = local.superadmins_aad_object_id

  depends_on = [
    azuread_group.groups
  ]
}


# Service Connections for ADO
# ---------------------------

module "service_connections" {
  for_each             = module.arm_environments # implicit dependency?
  source               = "./modules/azure-devops-service-connection"
  service_principal_id = each.value.service_principals[0].application_id
  key_vault_name       = each.value.key_vault
  resource_group_name  = each.value.resource_group_name
}
