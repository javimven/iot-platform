# Dockerfile de referencia (Etapa 9) para el monorepo NestJS del backend.
# Se activa cuando la Etapa 13 cree apps/backend/ con package.json real.
# Un único build sirve para los tres procesos (api/ingestion/worker,
# ARCHITECTURE.md sección 4) — cambia solo el entrypoint vía PROCESS_ROLE.

# ---- deps: instala dependencias con caché de capas ----
FROM node:20-alpine AS deps
WORKDIR /app
# El CLI `openssl` (no solo las librerías) tiene que estar disponible ANTES
# de `npm ci`: el postinstall de `@prisma/client` (`generate`) lo usa para
# detectar la versión real de OpenSSL de la imagen y elegir el binario de
# motor correcto (`linux-musl-openssl-3.0.x`, que es lo que trae de verdad
# `node:20-alpine`). Sin el CLI, la detección falla, cae por defecto a
# "openssl-1.1.x" (silencioso, solo un warning) y genera/empaqueta el
# binario equivocado — la imagen `runtime` final arranca pero **no puede
# conectar con Postgres en absoluto** ("Error loading shared library
# libssl.so.1.1: No such file or directory", `node:20-alpine` no trae esa
# librería, trae libssl.so.3). Bug real encontrado en vivo (2026-07-30) al
# construir el flujo de despliegue real: nunca se había probado el cliente
# de Prisma generado por este Dockerfile contra una base de datos real —
# `ci-cd.yml` ejecuta las pruebas de integración directamente en el runner
# de GitHub Actions (Ubuntu/glibc), nunca dentro de la imagen construida.
RUN apk add --no-cache openssl
COPY apps/backend/package.json apps/backend/package-lock.json ./
# `prisma/schema.prisma` tiene que estar presente ANTES de `npm ci`: el
# postinstall de `@prisma/client` (`generate`) lo necesita para generar los
# tipos; si no está, genera un cliente incompleto y `nest build` falla más
# adelante con decenas de errores de TypeScript (encontrado en vivo,
# 2026-07-29 — primera vez que este Dockerfile se construyó de verdad desde
# un checkout limpio en CI; en local no se detectó porque el `node_modules`
# del host, ya con el cliente bien generado, se colaba por encima en la
# etapa `build` al no existir `.dockerignore` — dos bugs distintos que se
# enmascaraban entre sí).
COPY apps/backend/prisma ./prisma
RUN npm ci

# ---- build: compila TypeScript (node_modules completo, con devDependencies) ----
FROM node:20-alpine AS build
WORKDIR /app
RUN apk add --no-cache openssl
COPY --from=deps /app/node_modules ./node_modules
COPY apps/backend/ .
# Regenera de todos modos, explícito e idempotente — no depender de que el
# postinstall de la etapa `deps` haya tenido todo lo que necesitaba.
RUN npx prisma generate && npm run build

# ---- prod-deps: instalación limpia, solo dependencias de producción ----
# Antes se reutilizaba el `node_modules` de `build` después de
# `npm prune --omit=dev` — bug real encontrado en vivo (2026-07-30): en el
# runner de GitHub Actions, `npm prune --omit=dev` dejó `eslint`/`jest`/
# `typescript`/`@nestjs/cli` completos dentro de la imagen final (362 MB en
# vez de 180 MB), con sus propias vulnerabilidades CRITICAL/HIGH (Trivy) —
# en local, con el mismo Dockerfile/lockfile, `prune` sí los quitaba. No se
# encontró la causa exacta de la discrepancia (probablemente una diferencia
# de comportamiento de `npm prune` entre entornos, ya documentada como poco
# fiable en general) — en vez de perseguirla, se eliminó la dependencia en
# `prune` por completo: una instalación `npm ci --omit=dev` dedicada es el
# camino principal y mejor probado de npm, no un caso secundario.
FROM node:20-alpine AS prod-deps
WORKDIR /app
RUN apk add --no-cache openssl
COPY apps/backend/package.json apps/backend/package-lock.json ./
COPY apps/backend/prisma ./prisma
RUN npm ci --omit=dev

# ---- runtime: imagen final, mínima ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S app && adduser -S app -G app \
  # Parchea OpenSSL de la imagen base (Trivy, CRITICAL/HIGH, ci-cd.yml) — la
  # base `node:20-alpine` trae libssl3/libcrypto3 sin el último parche.
  && apk upgrade --no-cache libssl3 libcrypto3 \
  # El CLI `openssl` hace falta AQUÍ TAMBIÉN, no solo en `deps`/`build`/
  # `prod-deps`: Prisma Client vuelve a detectar la versión de OpenSSL en
  # cada arranque del proceso (no solo al generar el cliente) para decidir
  # qué motor cargar — sin el CLI en esta etapa, esa segunda detección
  # también falla y por defecto busca la variante equivocada del motor
  # aunque el correcto ya esté empaquetado (bug real encontrado en vivo,
  # 2026-07-30, ver el comentario en la etapa `deps`).
  && apk add --no-cache openssl \
  # El `npm` (y `npx`/`corepack`) que trae la imagen base nunca se ejecuta en
  # tiempo de ejecución (ENTRYPOINT es "node dist/main.js" directo) — solo
  # aporta CVEs de sus propias dependencias internas (`tar`, `minimatch`,
  # `glob`...) sin exposición real, encontrado en vivo por Trivy en el primer
  # build real de esta imagen (2026-07-29). Se quita en vez de dejarlo como
  # peso muerto con vulnerabilidades.
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json
USER app

# PROCESS_ROLE decide qué entrypoint arranca (api|ingestion|worker).
# El script main.js interno lee la variable y bootstrapea solo los módulos
# necesarios (ARCHITECTURE.md sección 4) — no son tres imágenes distintas.
ENTRYPOINT ["node", "dist/main.js"]

# ---- migrator: solo para `prisma migrate deploy` en el momento del
# despliegue (DEPLOYMENT.md §9, infra/docker/deploy.sh) — se basa en `deps`
# (node_modules completo, con el CLI de `prisma`) porque `prisma` es una
# devDependency: `runtime` lo quita a propósito (nunca se ejecuta en el
# proceso servido — mismo criterio que quitar npm/npx de esa etapa) pero
# migrar el esquema sí necesita el CLI real, no solo `@prisma/client`.
# Nunca se referencia desde `runtime`, así que no le añade peso ni
# superficie de ataque a la imagen que de verdad queda expuesta al tráfico.
FROM deps AS migrator
WORKDIR /app
COPY apps/backend/prisma ./prisma
ENTRYPOINT ["npx", "prisma", "migrate", "deploy"]
