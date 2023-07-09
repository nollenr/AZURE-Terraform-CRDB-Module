locals {
  required_tags = {
    owner       = var.owner,
  }
  tags = merge(var.resource_tags, local.required_tags)
}

# HEY!  I only want to create the resource group in the first region!!

# Create a resource group
resource "azurerm_resource_group" "rg" {
  # Create this resource only if this is a single region install.  For multi region, the resource group will be passed in.
  count    = var.multi_region ? 0 : 1 
  name     = "${var.owner}-${var.resource_name}-rg"
  location = var.resource_group_location
  tags     = local.tags
}

locals {
  resource_group_name = var.multi_region ? var.multi_region_resource_group_name : one(azurerm_resource_group.rg[*].name)
}