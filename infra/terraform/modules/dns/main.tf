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
  # entornos, en un prefijo del MISMO nivel (staging-api.<domain>), no en un
  # subdominio anidado (api.staging.<domain>) — DEPLOYMENT.md §2. Corregido
  # en vivo (2026-08-04, primer despliegue real): el certificado Universal
  # SSL gratuito de Cloudflare solo cubre el dominio raíz y UN nivel de
  # subdominio (`*.<domain>`) — `api.staging.<domain>` tiene dos niveles y
  # queda fuera de esa cobertura (handshake_failure en el borde de
  # Cloudflare, confirmado contra la API real de certificados de la zona).
  # Cubrir subdominios anidados requiere Total TLS, un añadido de pago
  # (Advanced Certificate Manager) — se prefiere este esquema de nombres,
  # gratuito, en vez de pagar por algo evitable con un prefijo distinto.
  subdomain_prefix = var.environment == "production" ? "" : "${var.environment}-"
}

resource "cloudflare_dns_record" "api" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "${local.subdomain_prefix}api.${var.domain}"
  content = var.api_ipv4
  ttl     = 1 # "Automático" cuando proxied = true
  proxied = true
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "${local.subdomain_prefix}app.${var.domain}"
  content = var.api_ipv4
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "mqtt" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "${local.subdomain_prefix}mqtt.${var.domain}"
  content = var.mqtt_ipv4
  ttl     = 300
  proxied = false
}
