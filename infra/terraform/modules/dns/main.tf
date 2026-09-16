# Registros DNS de un entorno dentro de la zona ya creada (infra/terraform/dns-zone).
# Ninguno pasa por el proxy de Cloudflare: todos apuntan directamente al
# servidor. api/app lo estuvieron hasta el 2026-09-16 (HTTPS/CDN/mitigación
# básica de DoS), pero las IPs compartidas de Cloudflare que les tocaron
# (188.114.96.5 y 188.114.97.5) las bloquean Movistar, Orange, Vodafone, DIGI
# y MásMóvil por orden de LaLiga en días de fútbol (17 días entre julio y
# septiembre de 2026, de la tarde a la medianoche): la plataforma dejaba de
# abrir para cualquier cliente de esos operadores (BACKLOG.md #51). El TLS
# de api/app ya lo daba Caddy con Let's Encrypt en el origen; el de mqtt, EMQX.

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
  ttl     = 300
  proxied = false # ver la cabecera: bloqueos de IPs de Cloudflare en España
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "${local.subdomain_prefix}app.${var.domain}"
  content = var.api_ipv4
  ttl     = 300
  proxied = false # ver la cabecera: bloqueos de IPs de Cloudflare en España
}

resource "cloudflare_dns_record" "mqtt" {
  zone_id = data.cloudflare_zone.this.zone_id
  type    = "A"
  name    = "${local.subdomain_prefix}mqtt.${var.domain}"
  content = var.mqtt_ipv4
  ttl     = 300
  proxied = false
}
