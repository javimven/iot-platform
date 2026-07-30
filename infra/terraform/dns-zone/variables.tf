variable "domain" {
  description = "Dominio real registrado (DEPLOYMENT.md §6/§17 — `example.com` mientras no exista uno real)."
  type        = string
}

variable "cloudflare_account_id" {
  description = "ID de la cuenta de Cloudflare (Dashboard → Overview → Account ID, columna derecha)."
  type        = string
}
