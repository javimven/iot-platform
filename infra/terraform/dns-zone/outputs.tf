output "zone_id" {
  value = cloudflare_zone.this.id
}

output "name_servers" {
  description = "Servidores de nombres que Cloudflare asigna — hay que configurarlos en el registrador del dominio para delegar el DNS."
  value       = cloudflare_zone.this.name_servers
}
