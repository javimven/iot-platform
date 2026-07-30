variable "domain" {
  description = "Dominio real (DEPLOYMENT.md §6/§17) — debe coincidir con el usado al aplicar infra/terraform/dns-zone."
  type        = string
}

variable "ssh_public_key" {
  description = "Clave pública SSH para acceso administrativo al/a los servidor(es) de producción."
  type        = string
}

variable "admin_ssh_cidrs" {
  description = "CIDRs desde los que se permite SSH — nunca 0.0.0.0/0 (DEPLOYMENT.md §6)."
  type        = list(string)
}

variable "hetzner_location" {
  type    = string
  default = "fsn1"
}

variable "hetzner_server_type" {
  description = <<-EOT
    DEPLOYMENT.md §2/§8: producción corre `api` con 2 réplicas (Docker) —
    por defecto sobre 1 sola VPS más capaz que la de staging. Validar contra
    carga real antes de fijarlo (DEPLOYMENT.md §10).
  EOT
  type        = string
  default     = "cpx32"
}

variable "hetzner_server_count" {
  description = <<-EOT
    Número de VPS de producción — 1 por defecto (2 réplicas de `api` como
    contenedores en la misma VPS). Subir a 2 solo cuando el volumen real lo
    justifique (DEPLOYMENT.md §8/§17) — implica revisar también el módulo
    `dns` (hoy asume una sola IP de API/MQTT).
  EOT
  type        = number
  default     = 1
}

variable "do_region" {
  type    = string
  default = "fra1"
}

variable "do_database_size" {
  description = "Tier de producción de DO Managed Postgres — mayor que staging (DEPLOYMENT.md §2)."
  type        = string
  default     = "db-s-2vcpu-4gb"
}

variable "object_storage_access_key" {
  type = string
}

variable "object_storage_secret_key" {
  type      = string
  sensitive = true
}
