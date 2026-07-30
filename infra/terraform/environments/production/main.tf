# Entorno producción (DEPLOYMENT.md §2) — completamente aislado de staging:
# sin credenciales ni datos compartidos (DEPLOYMENT.md §2/§13). El módulo
# `dns` asume que la API/MQTT viven en el primer servidor — si
# `hetzner_server_count` sube por encima de 1, revisar también cómo se
# reparte el tráfico (Caddy/balanceador, DEPLOYMENT.md §8) antes de asumir
# que `server_ipv4_addresses[0]` sigue siendo suficiente.

locals {
  environment = "production"
}

module "compute" {
  source = "../../modules/compute"

  environment     = local.environment
  server_count    = var.hetzner_server_count
  server_type     = var.hetzner_server_type
  location        = var.hetzner_location
  ssh_public_key  = var.ssh_public_key
  admin_ssh_cidrs = var.admin_ssh_cidrs
}

module "database" {
  source = "../../modules/database"

  environment            = local.environment
  region                 = var.do_region
  size                   = var.do_database_size
  trusted_ipv4_addresses = module.compute.server_ipv4_addresses
}

module "object_storage" {
  source = "../../modules/object_storage"

  environment = local.environment
  access_key  = var.object_storage_access_key
  secret_key  = var.object_storage_secret_key
}

module "dns" {
  source = "../../modules/dns"

  domain      = var.domain
  environment = local.environment
  api_ipv4    = module.compute.server_ipv4_addresses[0]
  mqtt_ipv4   = module.compute.server_ipv4_addresses[0]
}
