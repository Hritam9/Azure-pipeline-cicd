terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-devops-demo"
  location = "East US"
}

# Storage Account
resource "azurerm_storage_account" "sa" {
  name                     = "devopsdemostgfunc"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan (Premium)
resource "azurerm_service_plan" "plan" {
  name                = "asp-devops-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "EP1"
  worker_count        = 1
}

# Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vn-devops-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "sub-devops-demo"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Web"]
  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Private DNS Zone
resource "azurerm_private_dns_zone" "dns" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dnslink" {
  name                  = "dnslink"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

# Function Apps definition
locals {
  function_apps = {
    "funcapp1" = {
      name     = "funcapp-demo-a1"
    },
    "funcapp2" = {
      name     = "funcapp-demo-a2"
    }
  }
}

# Function Apps
resource "azurerm_linux_function_app" "funcapps" {
  for_each = local.function_apps

  name                       = each.value.name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  functions_extension_version = "~4"
}

# VNet Integration (via subnet delegation)
resource "azurerm_app_service_virtual_network_swift_connection" "integration" {
  for_each = azurerm_linux_function_app.funcapps

  app_service_id = each.value.id
  subnet_id      = azurerm_subnet.subnet.id
}

# Private Endpoints
resource "azurerm_private_endpoint" "pe" {
  for_each = azurerm_linux_function_app.funcapps

  name                = "${each.key}-p"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "${each.key}-privatesc"
    private_connection_resource_id = each.value.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns.id]
  }
}
