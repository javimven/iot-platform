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
