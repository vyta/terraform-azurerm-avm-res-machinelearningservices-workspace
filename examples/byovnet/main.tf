terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.115"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/regions/azurerm"
  version = "~> 0.3"
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.3"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

module "private_dns_aml_api" {
  source              = "Azure/avm-res-network-privatednszone/azurerm"
  version             = "0.1.2"
  domain_name         = "privatelink.api.azureml.ms"
  resource_group_name = azurerm_resource_group.this.name
  virtual_network_links = {
    dnslink = {
      vnetlinkname = "privatelink.api.azureml.ms"
      vnetid       = module.virtual_network.resource.id
    }
  }
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
module "private_dns_aml_notebooks" {
  source              = "Azure/avm-res-network-privatednszone/azurerm"
  version             = "0.1.2"
  domain_name         = "privatelink.notebooks.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  virtual_network_links = {
    dnslink = {
      vnetlinkname = "privatelink.api.azureml.ms"
      vnetid       = module.virtual_network.resource.id
    }
  }
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
module "virtual_network" {
  source              = "Azure/avm-res-network-virtualnetwork/azurerm"
  version             = "~> 0.2.0"
  resource_group_name = azurerm_resource_group.this.name
  subnets = {
    private_endpoints = {
      name                              = "private_endpoints"
      address_prefixes                  = ["10.1.1.0/24"]
      private_endpoint_network_policies = "Enabled"
      service_endpoints                 = null
    }
  }
  address_space = ["10.1.0.0/16"]
  location      = var.location
  name          = module.naming.virtual_network.name_unique
  tags          = var.tags
}

resource "azurerm_container_registry" "example" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.container_registry.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Premium"
}

module "private_dns_keyvault" {
  source              = "Azure/avm-res-network-privatednszone/azurerm"
  version             = "~> 0.1.1"
  domain_name         = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  virtual_network_links = {
    dnslink = {
      vnetlinkname = "vaultcore-vnet-link"
      vnetid       = module.virtual_network.resource.id
    }
  }
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# This is the module call
# Do not specify location here due to the randomization above.
# Leaving location as `null` will cause the module to use the resource group location
# with a data source.


module "azureml" {
  source = "../../"
  # source             = "Azure/avm-<res/ptn>-<name>/azurerm"
  # ...
  location = var.location
  name     = module.naming.machine_learning_workspace.name_unique
  resource_group = {
    name = azurerm_resource_group.this.name
    id   = azurerm_resource_group.this.id
  }

  private_endpoints = {
    api = {
      name                            = "pe-api-aml"
      subnet_resource_id              = module.virtual_network.subnets["private_endpoints"].resource_id
      subresource_name                = "privatelink.api.azureml.ms"
      private_dns_zone_resource_ids   = [module.private_dns_aml_api.resource_id]
      private_service_connection_name = "psc-api-aml"
      network_interface_name          = "nic-pe-api-aml"
      inherit_lock                    = false
    }
    notebooks = {
      name                            = "pe-notebooks-aml"
      subnet_resource_id              = module.virtual_network.subnets["private_endpoints"].resource_id
      subresource_name                = "privatelink.notebooks.azure.net"
      private_dns_zone_resource_ids   = [module.private_dns_aml_notebooks.resource_id]
      private_service_connection_name = "psc-notebooks-aml"
      network_interface_name          = "nic-pe-notebooks-aml"
      inherit_lock                    = false
    }
  }

  enable_telemetry = var.enable_telemetry
}
