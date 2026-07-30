variable "environment" {
  description = "Nombre del entorno (staging | production) — usado para etiquetar y nombrar recursos."
  type        = string
}

variable "server_count" {
  description = <<-EOT
    Número de servidores `api` a crear. DEPLOYMENT.md §2/§8: staging = 1
    (todo-en-uno), producción = 1 por defecto (2 réplicas de `api` corren
    como contenedores Docker en el mismo servidor detrás de Caddy — no son
    2 VPS separadas hasta que el volumen real lo justifique, DEPLOYMENT.md
    §17). Subir a 2+ aquí solo cuando haya métricas reales que lo pidan.
  EOT
  type        = number
  default     = 1
}

variable "server_type" {
  description = <<-EOT
    Tipo de servidor Hetzner Cloud (p. ej. `cx23`, `cpx32`) — validar contra
    carga real antes de fijarlo en producción (DEPLOYMENT.md §10, no pagar
    por capacidad sin medir). `cx22` está retirado para pedidos nuevos desde
    enero de 2026 en la mayoría de ubicaciones.
  EOT
  type        = string
}

variable "location" {
  description = "Ubicación Hetzner Cloud (p. ej. `nbg1`, `fsn1`, `hel1`) — Alemania/Finlandia, DEPLOYMENT.md §1 (RGPD)."
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "Clave pública SSH (contenido del .pub) para el acceso administrativo inicial."
  type        = string
}

variable "admin_ssh_cidrs" {
  description = <<-EOT
    Lista de CIDR desde los que se permite SSH (puerto 22). Nunca
    `0.0.0.0/0` — DEPLOYMENT.md §6/§18 ("nunca abierto a cualquier IP").
    Sin valor por defecto a propósito: hay que fijarlo explícitamente.
  EOT
  type        = list(string)
  validation {
    condition     = length(var.admin_ssh_cidrs) > 0 && !contains(var.admin_ssh_cidrs, "0.0.0.0/0")
    error_message = "admin_ssh_cidrs no puede estar vacío ni incluir 0.0.0.0/0 (DEPLOYMENT.md §6/§18)."
  }
}

variable "labels" {
  description = "Etiquetas adicionales para atribución de coste (DEPLOYMENT.md §10)."
  type        = map(string)
  default     = {}
}
