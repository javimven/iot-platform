# Cómputo Hetzner Cloud (DEPLOYMENT.md §1/§6/§8): servidor(es) `api`, con
# firewall restrictivo (solo 443/8883/22, 22 acotado a IPs de administración
# conocidas) y clave SSH propia del entorno.

resource "hcloud_ssh_key" "this" {
  name       = "${var.environment}-admin-key"
  public_key = var.ssh_public_key
}

resource "hcloud_firewall" "this" {
  name = "${var.environment}-firewall"

  # HTTPS/WSS (API + app Flutter web) — público, DEPLOYMENT.md §6.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # MQTTS — público (los gateways de cualquier instalación cliente se
  # conectan desde IPs no acotables de antemano). Cloudflare gratuito NO
  # protege este puerto (DEPLOYMENT.md §11) — depende solo de este firewall
  # y del rate limiting de EMQX.
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8883"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # SSH — nunca abierto a cualquier IP (DEPLOYMENT.md §6/§18).
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_ssh_cidrs
  }
}

resource "hcloud_server" "api" {
  count = var.server_count

  name        = var.server_count > 1 ? "${var.environment}-api-${count.index + 1}" : "${var.environment}-api"
  image       = "debian-12"
  server_type = var.server_type
  location    = var.location

  ssh_keys     = [hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.this.id]

  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
  })

  lifecycle {
    # El aprovisionamiento del contenido (Docker, Caddy, docker-compose de
    # despliegue) lo hace el pipeline de CI/CD por SSH (DEPLOYMENT.md §9,
    # paso 9/12), no cloud-init — evita que un cambio de imagen fuerce un
    # recreate accidental del servidor.
    ignore_changes = [user_data]
  }
}
