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
