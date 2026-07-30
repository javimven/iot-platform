output "server_ipv4_addresses" {
  description = "IPs públicas IPv4 de los servidores `api` creados, en orden."
  value       = [for s in hcloud_server.api : s.ipv4_address]
}

output "server_ids" {
  description = "IDs de los servidores Hetzner Cloud creados."
  value       = [for s in hcloud_server.api : s.id]
}

output "firewall_id" {
  description = "ID del firewall aplicado a los servidores de este entorno."
  value       = hcloud_firewall.this.id
}
