variable "environment" {
  description = "Nombre del entorno (staging | production)."
  type        = string
}

variable "region" {
  description = "Región Hetzner Object Storage (`fsn1`, `hel1` o `nbg1`) — determina el endpoint `<region>.your-objectstorage.com`."
  type        = string
  default     = "fsn1"
}

variable "access_key" {
  description = <<-EOT
    Credencial de acceso S3 para Hetzner Object Storage. A diferencia del
    resto de recursos, Object Storage no usa el token de la API de Hetzner
    Cloud — la credencial se genera a mano en la consola (Object Storage no
    tiene API declarativa propia todavía, DEPLOYMENT.md §1).
  EOT
  type        = string
}

variable "secret_key" {
  description = "Secreto de acceso S3 correspondiente a `access_key`."
  type        = string
  sensitive   = true
}

variable "cors_allowed_origins" {
  description = <<-EOT
    Orígenes web que pueden descargar objetos del bucket desde el navegador
    (las imágenes de NDVI del módulo de satélite, BACKLOG.md #36). La app web
    se compila en WebAssembly, y ese motor lee las imágenes con `fetch`: sin
    CORS en el bucket, una imagen de otro dominio no se puede pintar de forma
    fiable dentro del mapa. Vacío = sin política CORS (el bucket sigue
    privado igualmente: sin URL firmada no se descarga nada).
  EOT
  type        = list(string)
  default     = []
}
