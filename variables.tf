variable "location" {
  description = "Azure location"
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "rg-funcapp-demo"
}

variable "client_id" {
  description = "Azure client ID"
  sensitive   = true
}

variable "client_secret" {
  description = "Azure client secret"
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure tenant ID"
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure subscription ID"
  sensitive   = true
}

variable "function_apps" {
  description = "Map of Function Apps"
  type = map(object({
    name    = string
    storage = string
    version = string
  }))
  default = {
    app1 = {
      name    = "funcapp-one"
      storage = "funcappstorageone"
      version = "~4"
    },
    app2 = {
      name    = "funcapp-two"
      storage = "funcappstoragetwo"
      version = "~4"
    }
  }
}
