output "join_string" {
  description = "the CockroachDB private IP join string"
  value = local.join_string
}

output "virtual_network_name" {
  description = "Virtual Network Name"
  value = azurerm_virtual_network.vm01.name
}

output "virtual_network_id" {
  description = "virtual Network ID"
  value = azurerm_virtual_network.vm01.id
}
