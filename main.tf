locals {
  required_tags = {
    owner       = var.owner,
  }
  tags = merge(var.resource_tags, local.required_tags)
}

# HEY!  I only want to create the resource group in the first region!!

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.owner}-${var.resource_name}-rg"
  location = var.resource_group_location
  tags = local.tags
}
