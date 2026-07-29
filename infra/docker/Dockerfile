# Dockerfile de referencia (Etapa 9) para el monorepo NestJS del backend.
# Se activa cuando la Etapa 13 cree apps/backend/ con package.json real.
# Un único build sirve para los tres procesos (api/ingestion/worker,
# ARCHITECTURE.md sección 4) — cambia solo el entrypoint vía PROCESS_ROLE.

# ---- deps: instala dependencias con caché de capas ----
FROM node:20-alpine AS deps
WORKDIR /app
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

# ---- build: compila TypeScript ----
FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY apps/backend/ .
# Regenera de todos modos, explícito e idempotente — no depender de que el
# postinstall de la etapa `deps` haya tenido todo lo que necesitaba.
RUN npx prisma generate \
  && npm run build \
  && npm prune --omit=dev

# ---- runtime: imagen final, mínima ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S app && adduser -S app -G app \
  # Parchea OpenSSL de la imagen base (Trivy, CRITICAL/HIGH, ci-cd.yml) — la
  # base `node:20-alpine` trae libssl3/libcrypto3 sin el último parche.
  && apk upgrade --no-cache libssl3 libcrypto3 \
  # El `npm` (y `npx`/`corepack`) que trae la imagen base nunca se ejecuta en
  # tiempo de ejecución (ENTRYPOINT es "node dist/main.js" directo) — solo
  # aporta CVEs de sus propias dependencias internas (`tar`, `minimatch`,
  # `glob`...) sin exposición real, encontrado en vivo por Trivy en el primer
  # build real de esta imagen (2026-07-29). Se quita en vez de dejarlo como
  # peso muerto con vulnerabilidades.
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json
USER app

# PROCESS_ROLE decide qué entrypoint arranca (api|ingestion|worker).
# El script main.js interno lee la variable y bootstrapea solo los módulos
# necesarios (ARCHITECTURE.md sección 4) — no son tres imágenes distintas.
ENTRYPOINT ["node", "dist/main.js"]
