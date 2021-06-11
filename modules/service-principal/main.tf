# Service Principal
# ------------------

resource "random_password" "sp_password" {
  length           = 30
  special          = true
  min_numeric      = 5
  min_special      = 2
  override_special = "-_%@?"
}

resource "azuread_application" "app" {
  display_name = local.name
}

resource "azuread_application_password" "workspace_sp_secret" {
  application_object_id = azuread_application.app.object_id
  value                 = random_password.sp_password.result
  end_date_relative     = var.password_lifetime
}

resource "azuread_service_principal" "sp" {
  application_id = azuread_application.app.application_id
}
