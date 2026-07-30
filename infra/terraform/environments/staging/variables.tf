variable "domain" {
  description = "Dominio real (DEPLOYMENT.md §6/§17) — debe coincidir con el usado al aplicar infra/terraform/dns-zone."
  type        = string
}

variable "ssh_public_key" {
  description = "Clave pública SSH para acceso administrativo al servidor de staging."
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
  description = "DEPLOYMENT.md §2: staging = \"1 VPS Hetzner pequeña (todo-en-uno)\"."
  type        = string
  default     = "cx23"
}

variable "do_region" {
  type    = string
  default = "fra1"
}

variable "do_database_size" {
  description = "Tier mínimo de DO Managed Postgres para staging (DEPLOYMENT.md §2)."
  type        = string
  default     = "db-s-1vcpu-2gb"
}

variable "object_storage_access_key" {
  type = string
}

variable "object_storage_secret_key" {
  type      = string
  sensitive = true
}
