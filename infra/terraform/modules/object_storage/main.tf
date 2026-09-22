# Hetzner Object Storage (S3-compatible) — DEPLOYMENT.md §1/§7: un bucket
# por entorno. Sin recurso nativo `hcloud_*` para esto todavía (a fecha de
# escritura); se gestiona vía el provider `minio` contra el endpoint
# S3-compatible de Hetzner, patrón documentado por el propio Hetzner
# (docs.hetzner.com/storage/object-storage/getting-started/creating-a-bucket-minio-terraform).

terraform {
  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.33"
    }
  }
}

provider "minio" {
  minio_server   = "${var.region}.your-objectstorage.com"
  minio_user     = var.access_key
  minio_password = var.secret_key
  minio_region   = var.region
  minio_ssl      = true
}

resource "minio_s3_bucket" "this" {
  bucket = "iot-platform-${var.environment}"
  acl    = "private"
}

# CORS de solo lectura para la app web (BACKLOG.md #36). No abre el bucket:
# sigue siendo privado, y sin una URL firmada por el backend no se descarga
# nada. Lo que permite es que el navegador, con una URL firmada válida, pueda
# pasarle la imagen al motor de Flutter web en vez de bloquearla por venir de
# otro dominio. Solo GET/HEAD: la app nunca sube nada directamente al bucket.
resource "minio_s3_bucket_cors" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = minio_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}
