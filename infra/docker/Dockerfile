# Dockerfile de referencia (Etapa 9) para el monorepo NestJS del backend.
# Se activa cuando la Etapa 13 cree apps/backend/ con package.json real.
# Un único build sirve para los tres procesos (api/ingestion/worker,
# ARCHITECTURE.md sección 4) — cambia solo el entrypoint vía PROCESS_ROLE.

# ---- deps: instala dependencias con caché de capas ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY apps/backend/package.json apps/backend/package-lock.json ./
RUN npm ci --omit=dev=false

# ---- build: compila TypeScript ----
FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY apps/backend/ .
RUN npm run build \
  && npm prune --omit=dev

# ---- runtime: imagen final, mínima ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json
USER app

# PROCESS_ROLE decide qué entrypoint arranca (api|ingestion|worker).
# El script main.js interno lee la variable y bootstrapea solo los módulos
# necesarios (ARCHITECTURE.md sección 4) — no son tres imágenes distintas.
ENTRYPOINT ["node", "dist/main.js"]
