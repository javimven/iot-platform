variable "domain" {
  description = "Dominio real (para buscar la zona ya creada por infra/terraform/dns-zone)."
  type        = string
}

variable "environment" {
  description = "Nombre del entorno (staging | production)."
  type        = string
}

variable "api_ipv4" {
  description = "IP pública del servidor que expone la API (primer servidor `api` del entorno)."
  type        = string
}

variable "mqtt_ipv4" {
  description = "IP pública del broker MQTT (normalmente el mismo servidor que la API en el MVP)."
  type        = string
}
