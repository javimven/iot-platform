# Registros DNS de un entorno dentro de la zona ya creada (infra/terraform/dns-zone) —
# DEPLOYMENT.md §6: api/app proxiadas por Cloudflare (HTTPS/CDN/mitigación
# básica de DoS), mqtt SIN proxiar (Cloudflare gratuito no proxia TCP puro,
# solo lo resolvería mal) — TLS de mqtt lo gestiona EMQX directamente
# (Let's Encrypt vía acme.sh), no Caddy.

data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

locals {
  # Producción vive en el propio dominio (api.<domain>); el resto de
  # entornos, en un subdominio (api.staging.<domain>) — DEPLOYMENT.md §2.
  subdomain_prefix = var.environment == "production" ? "" : "${var.environment}."
}

resource "cloudflare_dns_record" "api" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "api.${local.subdomain_prefix}${var.domain}"
  content = var.api_ipv4
  ttl     = 1 # "Automático" cuando proxied = true
  proxied = true
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "app.${local.subdomain_prefix}${var.domain}"
  content = var.api_ipv4
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "mqtt" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "mqtt.${local.subdomain_prefix}${var.domain}"
  content = var.mqtt_ipv4
  ttl     = 300
  proxied = false
}
