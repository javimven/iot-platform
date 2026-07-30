# Terraform — infraestructura real (Etapa 9)

Implementa las decisiones ya tomadas en [`docs/DEPLOYMENT.md`](../../docs/DEPLOYMENT.md)
(Hetzner Cloud + DigitalOcean Managed Postgres + Hetzner Object Storage +
Cloudflare DNS). **Nada de esto se ha aplicado todavía** — son declaraciones
listas para revisar y ejecutar cuando existan cuentas reales en los tres
proveedores y un dominio registrado (`DEPLOYMENT.md` §17).

## Estructura

```
infra/terraform/
  dns-zone/            # Zona Cloudflare del dominio real — se aplica UNA sola vez
  modules/
    compute/           # Servidor(es) Hetzner Cloud + firewall + clave SSH
    database/          # DigitalOcean Managed PostgreSQL + firewall + usuario de app
    object_storage/     # Bucket S3-compatible en Hetzner Object Storage
    dns/                # Registros DNS (api/app/mqtt) dentro de la zona ya creada
  environments/
    staging/            # Todo-en-uno, 1 VPS pequeña
    production/         # 1 VPS más capaz (2 réplicas de `api` como contenedores)
```

`staging` y `production` están completamente aislados entre sí: cuentas de
proveedor pueden compartirse (es la misma organización), pero cada uno tiene
su propio estado, sus propios recursos y ninguna credencial cruzada
(`DEPLOYMENT.md` §2/§13).

## Requisitos previos

1. **Cuentas** en Hetzner Cloud, DigitalOcean y Cloudflare.
2. **Dominio real** registrado en cualquier registrador (Cloudflare no
   registra dominios directamente en todos los TLD) — `DEPLOYMENT.md` §17.
3. Tokens de API de cada proveedor (nunca en archivos versionados — ver
   sección "Secretos" más abajo):
   - Hetzner Cloud: Consola → Proyecto → Security → API Tokens (permisos
     lectura+escritura).
   - DigitalOcean: Dashboard → API → Generate New Token.
   - Cloudflare: Dashboard → My Profile → API Tokens → Create Token (plantilla
     "Edit zone DNS", ampliada con permiso de creación de zona si vas a
     aplicar `dns-zone`).
4. Credencial S3 de Hetzner Object Storage — Consola → Object Storage →
   Generar credencial (independiente del token de la Cloud API).
5. Una clave SSH propia para administración (`ssh-keygen -t ed25519`) — la
   pública va en `terraform.tfvars`, la privada nunca sale de tu máquina.
6. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9.

## Orden de aplicación

```
1. dns-zone            (una sola vez, cualquier entorno la referencia después)
2. environments/staging
3. environments/production
```

`dns-zone` va primero porque `modules/dns` busca la zona ya creada por
nombre (`data "cloudflare_zone"`) — sin la zona, el `plan` de cualquier
entorno falla al no encontrarla.

## Uso (por cada directorio: `dns-zone`, `environments/staging`, `environments/production`)

```bash
cd infra/terraform/dns-zone   # o environments/staging, o environments/production

cp terraform.tfvars.example terraform.tfvars
# Edita terraform.tfvars con valores reales — este archivo nunca se versiona.

export HCLOUD_TOKEN="..."
export DIGITALOCEAN_TOKEN="..."
export CLOUDFLARE_API_TOKEN="..."

terraform init
terraform plan    # revisa el plan con calma antes de aplicar nada
terraform apply
```

Tras aplicar `dns-zone`, apunta los *nameservers* del dominio (output
`name_servers`) en tu registrador — Cloudflare no gestiona DNS de verdad
hasta que la delegación se complete (puede tardar hasta 24h).

## Secretos — nunca en el repositorio

- `terraform.tfvars` de cada directorio (credenciales de Object Storage,
  clave SSH pública, CIDRs de administración) — ya en `.gitignore`.
- Los tokens de proveedor (`HCLOUD_TOKEN`, `DIGITALOCEAN_TOKEN`,
  `CLOUDFLARE_API_TOKEN`) se pasan como variables de entorno, nunca como
  variables de Terraform con valor por defecto.
- En CI/CD, estos mismos tokens viven en **GitHub Actions Environments**
  (`staging`/`production`), coherente con `DEPLOYMENT.md` §4 — el pipeline
  de despliegue (paso 9/12) los usa para SSH + `docker compose pull/up`, no
  para ejecutar Terraform en cada despliegue (Terraform es para cambios de
  infraestructura, no para cada release de código).

## Estado (`terraform.tfstate`)

Por ahora, **estado local** (`backend "local"` en cada `versions.tf`) —
suficiente mientras una sola persona aplique cambios de infraestructura
(`DEPLOYMENT.md`, filosofía "sin complejidad sin necesidad medida"). Antes
de que más de una persona necesite aplicar Terraform con regularidad,
migrar a un backend remoto — el propio Hetzner Object Storage ya creado
por `modules/object_storage` sirve como backend S3-compatible (ver
[comunidad Hetzner: usar Object Storage como backend de Terraform](https://community.hetzner.com/tutorials/howto-hcloud-s3-terraform-backend/)),
sin necesidad de un cuarto proveedor solo para esto.

**Mientras el estado sea local**: haz una copia de seguridad de cada
`terraform.tfstate` fuera del propio directorio (nunca en el repositorio,
per contiene datos sensibles en claro) — perderlo significa que Terraform
ya no sabe qué recursos reales existen y podría intentar recrearlos.

## Qué NO cubre este directorio

- **Qué corre dentro de cada servidor** (Docker Compose de despliegue,
  Caddyfile con el dominio real, configuración de EMQX/TLS) — Terraform
  aprovisiona la VPS, el propio pipeline de CI/CD (`DEPLOYMENT.md` §9,
  pasos 9/12, hoy con marcadores de posición) es quien instala/actualiza lo
  que corre encima vía SSH. Ver `DEPLOYMENT.md` §5 para el `docker-compose.yml`
  de desarrollo local (referencia de qué servicios hacen falta) — el de
  despliegue real todavía no existe como entregable propio.
- El bootstrap del rol de aplicación restringido en Postgres
  (`iot_platform_app` sin `BYPASSRLS`, equivalente a
  `infra/docker/postgres-init/01-app-role.sql` en local) — ese paso vive en
  las migraciones/pipeline de despliegue, no en Terraform (ver comentario
  en `modules/database/main.tf`).
- Registro del dominio en sí — hazlo en el registrador que prefieras antes
  de aplicar `dns-zone`.

## Validado (sin aplicar nada real)

`terraform fmt`, `terraform validate` y `terraform plan` (con tokens de
formato válido pero credenciales falsas, para forzar a cada proveedor a
aceptar/rechazar la forma de las peticiones sin llegar a crear nada) se han
ejecutado contra los tres proveedores reales para los tres directorios
raíz (`dns-zone`, `environments/staging`, `environments/production`) — cada
recurso llegó a generar un plan de creación real (`digitalocean_database_cluster`,
`digitalocean_database_db`, `digitalocean_database_user`,
`digitalocean_database_firewall`, `minio_s3_bucket`, `hcloud_ssh_key`,
`hcloud_firewall`, `hcloud_server`, `cloudflare_zone`) y solo se detuvo en
el paso de autenticación real (token inválido, esperado). Ningún recurso
real ha sido creado.
