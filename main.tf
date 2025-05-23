provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-funcapps"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-funcapps"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Web"]
}

resource "azurerm_private_dns_zone" "dns" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dnslink" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

resource "azurerm_app_service_plan" "plan" {
  name                = "app-plan-premium"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "linux"
  reserved            = true

  sku {
    tier = "PremiumV2"
    size = "EP1"
  }
}

resource "azurerm_storage_account" "sa" {
  for_each = var.function_apps

  name                     = each.value.storage
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_function_app" "funcapps" {
  for_each = var.function_apps

  name                = each.value.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_app_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.sa[each.key].name
  storage_account_access_key = azurerm_storage_account.sa[each.key].primary_access_key
  version             = each.value.version
  os_type             = "linux"

  site_config {
    linux_fx_version = "Python|3.10"
  }
}

resource "azurerm_function_app_virtual_network_swift_connection" "vnetint" {
  for_each        = var.function_apps
  function_app_id = azurerm_linux_function_app.funcapps[each.key].id
  subnet_id       = azurerm_subnet.subnet.id
}

resource "azurerm_private_endpoint" "pep" {
  for_each            = var.function_apps
  name                = "${each.value.name}-pep"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "${each.value.name}-psc"
    private_connection_resource_id = azurerm_linux_function_app.funcapps[each.key].id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns.id]
  }
}
