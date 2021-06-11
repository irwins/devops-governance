data "azurerm_client_config" "current" {}

# ------
# Config
# ------

# Suffix - for globally unique resource names

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

# ---------------
# Azure AD Groups
# ---------------

resource "azuread_group" "groups" {
  for_each                = var.groups
  display_name            = "demo-${each.value}-${local.suffix}"
  prevent_duplicate_names = true
}

# ------------------
# Service Principals
# ------------------

# TODO: document use for CI only. Apps should use diff. SP per PILP

module "service_principals" {
  for_each = var.environments
  source   = "./modules/service-principal"
  name     = "${each.value.team}-${each.value.env}-${local.suffix}-ci-sp"
}

# --------------------------------
# Resource Groups ("Workspaces")
# --------------------------------

module "arm_environments" {
  for_each             = var.environments
  source               = "./modules/azure-resources"
  name                 = "${each.value.team}-${each.value.env}-${local.suffix}"
  devs_group_id        = azuread_group.groups["${each.value.team}_devs"].id
  admins_group_id      = azuread_group.groups["${each.value.team}_admins"].id
  superadmins_group_id = local.superadmins_aad_object_id
  service_principal_id = module.service_principals["${each.value.team}_${each.value.env}"].principal_id
}

# ------------
# Azure DevOps
# ------------

# The following section Bootstraps:
# - Projects: Team silos and shared projects
# - Security Group Assignments: like Role Assignments in ARM
# - Service Connections: service principal credentials created in code above

# Projects
# --------

# Team Projects

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

# Shared Collaboration Project (Only Azure Boards)

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

# Security Group Assignments
# --------------------------

# Teams Silo Projects -  Security Group Assignments

module "team_permissions" {
  for_each       = var.projects
  source         = "./modules/azure-devops-permissions"
  ado_project_id = azuredevops_project.team_projects["proj_${each.value.team}"].id
  team_aad_id    = azuread_group.groups["${each.value.team}_devs"].id     # Receives 'Contributor' Permissions
  admin_aad_id   = azuread_group.groups["${each.value.team}_admins"].id   # Receives 'Project Administrator' Permissions

  depends_on = [
    azuread_group.groups
  ]
}

# Supermarket Project - Security Group Assignments
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

# Collaboration Project - Security Group Assignments

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

# Service Connections
# -------------------

# module "service_connections" {
#   for_each             = module.arm_environments
#   source               = "./modules/azure-devops-service-connection"
#   service_principal_id = each.value.service_principals[0].application_id # Does this work???
#   key_vault_name       = each.value.key_vault # not needed
#   resource_group_name  = each.value.resource_group_name

#   depends_on = [
#     azuread_group.groups,
#     module.arm_environments,
#     module.service_principals
#   ]
# }
