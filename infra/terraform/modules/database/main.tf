# PostgreSQL administrado en DigitalOcean (DEPLOYMENT.md §1/§7): backups
# automáticos + PITR gestionados por DO, acceso restringido por IP — nunca
# expuesto sin firewall (DEPLOYMENT.md §6).

resource "digitalocean_database_cluster" "postgres" {
  name       = "${var.environment}-postgres"
  engine     = "pg"
  version    = var.postgres_version
  size       = var.size
  region     = var.region
  node_count = var.node_count
  tags       = concat(var.tags, [var.environment])
}

resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  dynamic "rule" {
    for_each = var.trusted_ipv4_addresses
    content {
      type  = "ip_addr"
      value = rule.value
    }
  }
}

resource "digitalocean_database_db" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "iot_platform"
}

# Usuario de aplicación — DigitalOcean nunca le da rol `primary`/superusuario
# a un usuario creado así (ver docs del provider), pero sigue haciendo falta
# el paso de migración que crea el rol restringido `iot_platform_app` con
# `BYPASSRLS` desactivado explícitamente (infra/docker/postgres-init/01-app-role.sql
# es el equivalente local) — responsabilidad del pipeline de despliegue, no
# de este módulo (DEPLOYMENT.md §9, pasos "Migrar esquema"/"Crear el rol de
# aplicación restringido", ya existentes para el Postgres efímero de CI).
resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "iot_platform_app"
}
