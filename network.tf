locals {
  subnet_list = cidrsubnets(var.virtual_network_cidr,3,3,3,3,3,3)
  private_subnet_list = chunklist(local.subnet_list,3)[0]
  public_subnet_list  = chunklist(local.subnet_list,3)[1]
}


resource "azurerm_virtual_network" "vm01" {
  name                = "${var.owner}-${var.resource_name}-network"
  location            = var.virtual_network_location
  resource_group_name = local.resource_group_name
  address_space       = [var.virtual_network_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "sn" {
  count                = 3
  name                 = "${var.owner}-${var.resource_name}-subnet-${count.index}"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vm01.name
  address_prefixes     = [local.public_subnet_list[count.index]]
  # tags are not a valid argument for subnets
}

resource "azurerm_network_security_group" "desktop-sg" {
    name                = "${var.owner}-${var.resource_name}-sg"
    location            = var.virtual_network_location
    resource_group_name = local.resource_group_name
    tags                = local.tags

    security_rule {
        name                       = "Desktop-Access-To-SSH-HTTP-CRDB"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_address_prefix      = "${var.my_ip_address}/32"
        source_port_range          = "*"
        destination_port_ranges    = [22,26257,8080]
        destination_address_prefix = "*"
    }
}

resource "azurerm_subnet_network_security_group_association" "desktop-access" {
  count                     = 3
  subnet_id                 = azurerm_subnet.sn[count.index].id
  network_security_group_id = azurerm_network_security_group.desktop-sg.id
}