output "service_principal" {
  value = {
    display_name   = azuread_application.app.display_name
    object_id      = azuread_application.app.object_id
    application_id = azuread_application.app.application_id
  }
}
