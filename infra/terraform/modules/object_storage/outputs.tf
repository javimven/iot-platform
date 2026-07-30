output "bucket_name" {
  value = minio_s3_bucket.this.bucket
}

output "endpoint" {
  description = "Endpoint S3-compatible (S3_ENDPOINT, DEPLOYMENT.md §3)."
  value       = "https://${var.region}.your-objectstorage.com"
}
