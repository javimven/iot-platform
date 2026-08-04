#!/usr/bin/env bash
# Script de despliegue de referencia (DEPLOYMENT.md §8/§9) — se ejecuta EN
# LA VPS (Hetzner Cloud, infra/terraform/modules/compute), en el mismo
# directorio que docker-compose.deploy.yml/Caddyfile/.env/web/ (copiados
# ahí por el pipeline de CI/CD vía SSH — hoy sigue siendo un `echo` de
# marcador de posición en .github/workflows/ci-cd.yml hasta que exista una
# VPS real donde invocar esto de verdad, DEPLOYMENT.md §9 pasos 9/12).
#
# Uso: IMAGE_TAG=<sha-del-commit> ./deploy.sh
#
# Requiere en el entorno (o en .env, que este script también carga):
#   IMAGE_TAG            — SHA del commit a desplegar (nunca "latest")
#   DATABASE_URL_MIGRATE — conexión con el usuario admin/propietario de
#                          DigitalOcean Managed Postgres (DDL + GRANT), NUNCA
#                          la misma que usan api/worker/ingestion
#                          (DATABASE_URL en .env, rol restringido
#                          `iot_platform_app` sin BYPASSRLS) — ver
#                          infra/docker/postgres-init/02-grant-app-role-managed.sql
#                          y el comentario en infra/terraform/modules/database/main.tf.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${IMAGE_TAG:?Falta IMAGE_TAG}"
: "${DATABASE_URL_MIGRATE:?Falta DATABASE_URL_MIGRATE (usuario admin de DO Managed Postgres, no el de la app)}"

MIGRATOR_IMAGE="ghcr.io/javimven/iot-platform:${IMAGE_TAG}-migrator"
COMPOSE="docker compose -f docker-compose.deploy.yml"

echo "==> Descargando imágenes (${IMAGE_TAG})"
$COMPOSE pull

echo "==> Concediendo privilegios al rol de aplicación (idempotente)"
docker run --rm --network host \
  -v "$(pwd)/postgres-init/02-grant-app-role-managed.sql:/grant.sql:ro" \
  postgres:16-alpine \
  psql "$DATABASE_URL_MIGRATE" -v ON_ERROR_STOP=1 -f /grant.sql

echo "==> Aplicando migraciones de esquema (como propietario de las tablas)"
docker run --rm --network host \
  -e DATABASE_URL="$DATABASE_URL_MIGRATE" \
  "$MIGRATOR_IMAGE"

# Catálogos de plataforma (roles, tipos de canal, features) + bootstrap del
# primer Admin de plataforma (prisma/seed.ts, PLATFORM_ADMIN_BOOTSTRAP_EMAIL/
# PASSWORD en .env) — idempotente (upsert), seguro de repetir en cada
# despliegue. `prisma migrate deploy` NUNCA ejecuta esto por sí solo; sin
# este paso, el primer login del bootstrap admin falla con 401 porque el
# usuario nunca llegó a crearse (bug real encontrado en vivo, 2026-08-04).
#
# `ts-node prisma/seed.ts` directo (CJS register hook, `-r ts-node/register`,
# y `--loader ts-node/esm`) falló de tres formas distintas contra Node 20 en
# este contenedor (ERR_UNKNOWN_FILE_EXTENSION, después ERR_REQUIRE_CYCLE_MODULE
# forzando el loader ESM) — problema real de compatibilidad ts-node 10.x/
# Node 20, no un error de sintaxis. Se evita del todo compilando el archivo
# a JS plano con `tsc` (dentro de /app para que Node resuelva node_modules al
# buscar hacia arriba desde el archivo) y ejecutando ese JS con `node` — cero
# dependencia del runtime de ts-node en producción, más robusto.
echo "==> Sembrando catálogos de plataforma y admin de plataforma (idempotente)"
docker run --rm --network host \
  --entrypoint sh \
  -e DATABASE_URL="$DATABASE_URL_MIGRATE" \
  -e PLATFORM_ADMIN_BOOTSTRAP_EMAIL="${PLATFORM_ADMIN_BOOTSTRAP_EMAIL:-}" \
  -e PLATFORM_ADMIN_BOOTSTRAP_PASSWORD="${PLATFORM_ADMIN_BOOTSTRAP_PASSWORD:-}" \
  "$MIGRATOR_IMAGE" -c '
    npx tsc prisma/seed.ts --outDir /app/prisma/dist --module commonjs \
      --target ES2022 --esModuleInterop --skipLibCheck --resolveJsonModule &&
    node /app/prisma/dist/seed.js
  '

# Despliegue sin interrupciones: una réplica de `api` cada vez, comprobando
# /health antes de tocar la siguiente (DEPLOYMENT.md §8) — nunca las dos
# caen a la vez.
wait_healthy() {
  local service="$1"
  local attempts=0
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$($COMPOSE ps -q "$service")" 2>/dev/null)" = "healthy" ]; do
    attempts=$((attempts + 1))
    if [ "$attempts" -gt 30 ]; then
      echo "!! $service no se puso sano a tiempo — abortando despliegue" >&2
      exit 1
    fi
    sleep 2
  done
}

echo "==> Desplegando api_1"
$COMPOSE up -d --no-deps api_1
wait_healthy api_1

echo "==> Desplegando api_2"
$COMPOSE up -d --no-deps api_2
wait_healthy api_2

# worker/ingestion sí tienen una breve ventana de reinicio — aceptable, no
# están sujetos al SLA de disponibilidad de la API/app (DEPLOYMENT.md §8).
echo "==> Desplegando worker e ingestion"
$COMPOSE up -d --no-deps worker ingestion

echo "==> Actualizando emqx/otel-collector/caddy si su imagen o configuración cambió"
$COMPOSE up -d --no-deps emqx otel-collector caddy

echo "==> Limpiando imágenes sin usar (más de 72h)"
docker image prune -f --filter "until=72h" >/dev/null

echo "==> Despliegue completo (${IMAGE_TAG})"
