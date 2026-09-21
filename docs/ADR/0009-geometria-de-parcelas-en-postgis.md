# ADR-0009: La geometría de las parcelas se guarda en PostGIS

- Estado: Aceptada
- Fecha: 2026-09-21

## Contexto

El módulo de satélite (BACKLOG.md #36) necesita el contorno real de la parcela: Sentinel-2 calcula el NDVI sobre ese polígono, no sobre el punto GPS de la finca. Hasta ahora lo único geográfico de la plataforma eran `installations.latitude` y `installations.longitude`, dos `double precision` opcionales.

Había dos caminos, y cuál era viable dependía de un dato que no estaba comprobado: si el PostgreSQL gestionado de DigitalOcean admite PostGIS.

**Comprobado el 2026-09-21 contra la base de staging real**: PostgreSQL **16.15**, con `postgis` **3.5.7** disponible (no instalada), además de `postgis_raster`, `postgis_topology`, `postgis_sfcgal` y `postgis_tiger_geocoder`. Las migraciones se ejecutan con `DATABASE_URL_MIGRATE` (el usuario admin del proveedor, `infra/docker/deploy.sh`), que es quien puede crear extensiones.

La alternativa era guardar el GeoJSON en una columna `jsonb` y calcular área, caja y validaciones en Node con `@turf/*`.

## Decisión

**PostGIS**, con la columna `geometry(MultiPolygon, 4326)` como única fuente de verdad (migración `0008_parcelas`).

- **MultiPolygon y no Polygon** aunque la v1 solo deje dibujar un recinto: una parcela partida por un camino es corriente, admitirlo hoy no cuesta nada y evita una migración sobre datos reales después. La aplicación acepta `Polygon` o `MultiPolygon` de entrada y normaliza con `ST_Multi`.
- **EPSG:4326** (WGS84, grados) porque es lo que hablan GeoJSON, las APIs de Copernicus y las coordenadas que ya guardaba `installations`. El área en metros sale de `ST_Area(geometry::geography)`, que mide sobre el elipsoide — medir en grados daría un número sin sentido físico.
- `area_m2` y la caja envolvente (`bbox_*`) se **desnormalizan** al guardar: se leen en cada listado sin tocar la columna pesada.
- **Índice GiST** desde el día uno. Hoy no hay ninguna consulta que lo use (las parcelas se leen por finca), pero crearlo sobre una tabla vacía es gratis y sobre una tabla con datos no lo es, y las preguntas que lo necesitan —"qué parcela contiene esta estación", "qué parcelas toca este tile"— llegarán solas.
- **El entorno local y el de CI pasan a `postgis/postgis:16-3.5-alpine`**, la imagen oficial de Postgres con la extensión: sin eso, la migración funciona en staging y falla en el portátil y en el CI. Misma línea 3.5 que la base gestionada.

## Consecuencias

**Lo que cuesta.** Prisma 5 no modela tipos geométricos, así que la columna va declarada como `Unsupported("geometry(MultiPolygon, 4326)")`. Eso tiene dos efectos concretos, no evitables:

1. **`prisma.parcel.create()` no es utilizable**: Prisma Client no puede rellenar un campo `Unsupported` obligatorio. El alta se hace con `$queryRaw`.
2. **`findMany` no devuelve la geometría**. Leer el contorno exige `ST_AsGeoJSON` en SQL crudo.

Ambas quedan encerradas en `ParcelsRepository`: el resto del módulo (servicio, controlador, jobs de satélite) trabaja con GeoJSON y no se entera de dónde está guardado. `update`, `delete` y cualquier lectura que no necesite el contorno siguen usando Prisma con normalidad, RLS incluido, porque el SQL crudo también va dentro de `runInTenantContext`.

**Lo que se gana.** Validación (`ST_IsValid`), área exacta, caja envolvente y, más adelante, consultas espaciales de verdad sin traer una librería ni reimplementar geodesia en JavaScript. Y la puerta abierta a `postgis_raster` si algún día interesa consultar los rásters desde la base.

**Lo que no se hace.** No se añade `@turf/*`: con PostGIS disponible sería una segunda implementación de lo mismo. No se instala `postgis_topology` ni `postgis_raster`: solo la extensión base.

## Alternativa descartada

GeoJSON en `jsonb` + `@turf/*`. Habría evitado el `Unsupported` de Prisma y el cambio de imagen en local/CI, y era la opción obligada si el proveedor no hubiese admitido la extensión. Se descarta porque el proveedor **sí** la admite: guardar geometría como texto JSON en una base que sabe geometría es renunciar a la validación y a las consultas espaciales para ahorrar un repositorio de cinco consultas.
