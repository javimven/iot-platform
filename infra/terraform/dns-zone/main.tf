# Zona Cloudflare del dominio real — se aplica UNA sola vez, por separado de
# staging/production (DEPLOYMENT.md §6): ambos entornos crean registros DNS
# dentro de esta misma zona (subdominios `staging.<dominio>` vs `<dominio>`),
# no zonas propias. `environments/*/dns.tf` la referencia como data source
# por nombre, no por estado remoto compartido — evita acoplar el estado de
# la zona al de cada entorno.

resource "cloudflare_zone" "this" {
  account = { id = var.cloudflare_account_id }
  name    = var.domain
  type    = "full"
}

# Subdominio de marca de Brevo (BACKLOG.md #55): los enlaces y las imágenes de
# los correos de la plataforma salen con el dominio propio en vez de con el de
# Brevo, y Brevo lo exige para dar el dominio por autenticado. Sin autenticar,
# Gmail descartaba los correos: durante septiembre de 2026 no llegó ninguna
# invitación ni recuperación de contraseña.
#
# Los otros registros que pide Brevo (el TXT `brevo-code`, los CNAME de DKIM
# `brevo1/brevo2._domainkey` y el TXT `_dmarc`) se crearon a mano en Cloudflare
# antes que esto y siguen fuera de Terraform; para traerlos habría que
# importarlos (`terraform import`), pendiente.
#
# Sin proxy, como todo lo demás de esta zona: el proxy de Cloudflare no pinta
# nada en registros de correo y además arrastra el problema de las IPs
# bloqueadas en España (BACKLOG.md #51).
resource "cloudflare_dns_record" "brevo_marca" {
  zone_id = cloudflare_zone.this.id
  type    = "CNAME"
  name    = "mail.${var.domain}"
  content = "mail-jmvsoluciones-com.brand.brevosend.com"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "brevo_redireccion" {
  zone_id = cloudflare_zone.this.id
  type    = "CNAME"
  name    = "r.mail.${var.domain}"
  content = "mail-jmvsoluciones-com.r.brand.brevosend.com"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "brevo_imagenes" {
  zone_id = cloudflare_zone.this.id
  type    = "CNAME"
  name    = "img.mail.${var.domain}"
  content = "mail-jmvsoluciones-com.img.brand.brevosend.com"
  ttl     = 3600
  proxied = false
}
