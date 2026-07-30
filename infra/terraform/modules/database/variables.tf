variable "environment" {
  description = "Nombre del entorno (staging | production)."
  type        = string
}

variable "region" {
  description = "Región DigitalOcean — `fra1` (Frankfurt), DEPLOYMENT.md §1 (RGPD, co-localizado con Hetzner UE)."
  type        = string
  default     = "fra1"
}

variable "postgres_version" {
  description = "Versión mayor de PostgreSQL."
  type        = string
  default     = "16"
}

variable "size" {
  description = <<-EOT
    Tier de DigitalOcean Managed Postgres (p. ej. `db-s-1vcpu-2gb` para
    staging, algo mayor para producción) — validar contra carga real,
    DEPLOYMENT.md §10.
  EOT
  type        = string
}

variable "node_count" {
  description = "Número de nodos (1 = sin standby de alta disponibilidad)."
  type        = number
  default     = 1
}

variable "trusted_ipv4_addresses" {
  description = <<-EOT
    IPs con permiso para conectar a la base de datos (las de los servidores
    `api`/`worker`, típicamente vía el output `server_ipv4_addresses` del
    módulo `compute`) — DEPLOYMENT.md §6 ("nunca expuestos... a internet").
    Sin valor por defecto a propósito.
  EOT
  type        = list(string)
  validation {
    condition     = length(var.trusted_ipv4_addresses) > 0
    error_message = "trusted_ipv4_addresses no puede estar vacío — la base de datos quedaría sin ninguna IP autorizada."
  }
}

variable "tags" {
  description = "Etiquetas para atribución de coste (DEPLOYMENT.md §10)."
  type        = list(string)
  default     = []
}
