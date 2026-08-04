output "host" {
  description = "Host de conexión (privado si el cluster está en una VPC de DO, público en caso contrario)."
  value       = digitalocean_database_cluster.postgres.host
}

output "port" {
  value = digitalocean_database_cluster.postgres.port
}

output "database_name" {
  value = digitalocean_database_db.app.name
}

output "app_user_name" {
  value = digitalocean_database_user.app.name
}

output "app_user_password" {
  value     = digitalocean_database_user.app.password
  sensitive = true
}

output "connection_string" {
  description = "DATABASE_URL lista para usar (DEPLOYMENT.md §3) — sensible, nunca loguear ni versionar."
  value       = "postgres://${digitalocean_database_user.app.name}:${digitalocean_database_user.app.password}@${digitalocean_database_cluster.postgres.host}:${digitalocean_database_cluster.postgres.port}/${digitalocean_database_db.app.name}?sslmode=require"
  sensitive   = true
}

output "admin_connection_string" {
  description = <<-EOT
    DATABASE_URL_MIGRATE (infra/docker/deploy.sh) — usuario admin/propietario
    por defecto del cluster (`doadmin`), nunca el rol restringido de la app.
    Solo para migrar el esquema y conceder privilegios, nunca para el
    tráfico normal de la aplicación. Construida a mano (no con el atributo
    `.uri` del cluster, que apunta por defecto a `defaultdb`) para que
    conecte contra la base real de la aplicación (`digitalocean_database_db.app`),
    donde `prisma migrate deploy` debe crear las tablas.
  EOT
  value       = "postgresql://${digitalocean_database_cluster.postgres.user}:${digitalocean_database_cluster.postgres.password}@${digitalocean_database_cluster.postgres.host}:${digitalocean_database_cluster.postgres.port}/${digitalocean_database_db.app.name}?sslmode=require"
  sensitive   = true
}
