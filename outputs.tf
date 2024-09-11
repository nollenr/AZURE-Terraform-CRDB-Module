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

output "tls_private_key" {
  description = "tls_private_key.crdb_ca_keys.private_key_pem -> ca.key / TLS Private Key PEM"
  value = local.tls_private_key
  sensitive = true
}

output "tls_public_key" {
  description = "tls_private_key.crdb_ca_keys.public_key_pem -> ca.pub / TLS Public Key PEM"
  value = local.tls_public_key
}

output "tls_cert" {
  description = "tls_self_signed_cert.crdb_ca_cert.cert_pem -> ca.crt / TLS Cert PEM  /  Duplicate of tls_cert for better naming"
  value = local.tls_cert
}

output "tls_user_cert" {
  description = "tls_locally_signed_cert.user_cert.cert_pem -> client.name.crt"
  value = local.tls_user_cert
}

output "tls_user_key" {
  description = "tls_private_key.client_keys.private_key_pem -> client.name.key"
  value = local.tls_user_key
  sensitive = true
}

