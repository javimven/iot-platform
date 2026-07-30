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
