output "server_ipv4_addresses" {
  value = module.compute.server_ipv4_addresses
}

output "database_connection_string" {
  value     = module.database.connection_string
  sensitive = true
}

output "object_storage_bucket" {
  value = module.object_storage.bucket_name
}

output "object_storage_endpoint" {
  value = module.object_storage.endpoint
}

output "api_hostname" {
  value = module.dns.api_hostname
}

output "app_hostname" {
  value = module.dns.app_hostname
}

output "mqtt_hostname" {
  value = module.dns.mqtt_hostname
}
