-- Observaciones de satélite (BACKLOG.md #36, fases 5-7). Dominio propio, no
-- canales de telemetría: un `channel` cuelga de un `sensor`, que es hardware,
-- y detrás de una imagen de Sentinel no hay ninguna sonda. Mezclarlos habría
-- obligado a inventar un sensor falso por parcela.
--
-- Migración SQL a mano, como el resto del esquema: RLS, CHECKs e índices
-- únicos no los expresa Prisma.

-- ---------------------------------------------------------------------------
-- Tipos. Conjuntos cerrados que controlamos nosotros, así que enum de verdad.
-- `provider`, `collection`, `metric_code` y `asset_type` NO son enums a
-- propósito: añadir Planet o NDRE no debe costar un ALTER TYPE en su propia
-- migración (restricción conocida de Postgres, ver migración 0007).
-- ---------------------------------------------------------------------------
CREATE TYPE "SatelliteObservationStatus" AS ENUM (
  'pending', 'processing', 'ready', 'rejected_quality', 'failed'
);

CREATE TYPE "SatelliteQualityStatus" AS ENUM ('good', 'partial', 'rejected');

-- ---------------------------------------------------------------------------
-- satellite_observations
--
-- Una fila = una pasada del satélite sobre una parcela, ya procesada. La clave
-- lógica es (parcela, proveedor, colección, día, versión de procesado):
--
--   * El DÍA y no el instante: una parcela a caballo de dos tiles recibe
--     varios items STAC de la misma pasada, con segundos de diferencia. Son
--     una sola observación, y sus identificadores quedan en `source_item_ids`.
--   * La VERSIÓN de procesado dentro de la clave: reprocesar con otro
--     evalscript o con otra máscara crea una fila nueva en vez de pisar la
--     anterior, y así se pueden comparar antes de tirar la vieja.
-- ---------------------------------------------------------------------------
CREATE TABLE satellite_observations (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         UUID NOT NULL REFERENCES organizations(id),
  parcel_id               UUID NOT NULL REFERENCES parcels(id),
  provider                TEXT NOT NULL,
  collection              TEXT NOT NULL,
  acquisition_time        TIMESTAMPTZ NOT NULL,
  acquisition_date        DATE NOT NULL,
  source_item_ids         JSONB NOT NULL DEFAULT '[]'::jsonb,
  platform                TEXT,
  processing_version      TEXT NOT NULL,
  parcel_geometry_version INTEGER NOT NULL,
  valid_pixel_fraction    DOUBLE PRECISION,
  parcel_cloud_fraction   DOUBLE PRECISION,
  scene_cloud_cover       DOUBLE PRECISION,
  quality_status          "SatelliteQualityStatus",
  status                  "SatelliteObservationStatus" NOT NULL DEFAULT 'pending',
  last_error              TEXT,
  processed_at            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT satellite_observations_fracciones CHECK (
    (valid_pixel_fraction IS NULL OR valid_pixel_fraction BETWEEN 0 AND 1) AND
    (parcel_cloud_fraction IS NULL OR parcel_cloud_fraction BETWEEN 0 AND 1) AND
    (scene_cloud_cover IS NULL OR scene_cloud_cover BETWEEN 0 AND 1)
  ),
  CONSTRAINT satellite_observations_items_es_lista CHECK (jsonb_typeof(source_item_ids) = 'array')
);

CREATE UNIQUE INDEX satellite_observations_logica_uniq
  ON satellite_observations (parcel_id, provider, collection, acquisition_date, processing_version);

CREATE INDEX satellite_observations_organization_id_idx
  ON satellite_observations (organization_id);

-- La serie temporal de una parcela se lee siempre así: por parcela y ordenada
-- por fecha de ADQUISICIÓN, nunca por la de procesado.
CREATE INDEX satellite_observations_parcel_id_acquisition_time_idx
  ON satellite_observations (parcel_id, acquisition_time);

-- ---------------------------------------------------------------------------
-- satellite_metrics
--
-- Una fila por índice y observación. Añadir NDRE o NDMI el día de mañana es
-- una fila más, no una columna más ni una tabla nueva.
-- ---------------------------------------------------------------------------
CREATE TABLE satellite_metrics (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  observation_id  UUID NOT NULL REFERENCES satellite_observations(id) ON DELETE CASCADE,
  metric_code     TEXT NOT NULL,
  mean            DOUBLE PRECISION NOT NULL,
  median          DOUBLE PRECISION NOT NULL,
  min             DOUBLE PRECISION NOT NULL,
  max             DOUBLE PRECISION NOT NULL,
  std_dev         DOUBLE PRECISION NOT NULL,
  p10             DOUBLE PRECISION NOT NULL,
  p90             DOUBLE PRECISION NOT NULL,
  sample_count    INTEGER NOT NULL,
  no_data_count   INTEGER NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT satellite_metrics_recuentos CHECK (sample_count >= 0 AND no_data_count >= 0),
  CONSTRAINT satellite_metrics_orden CHECK (min <= max)
);

CREATE UNIQUE INDEX satellite_metrics_observation_id_metric_code_key
  ON satellite_metrics (observation_id, metric_code);

CREATE INDEX satellite_metrics_organization_id_idx ON satellite_metrics (organization_id);

-- ---------------------------------------------------------------------------
-- satellite_assets
--
-- Dónde está cada archivo en el almacenamiento de objetos. El objeto en sí
-- nunca se sirve directamente: se firma una URL con caducidad
-- (`StorageService`), y el bucket es privado.
-- ---------------------------------------------------------------------------
CREATE TABLE satellite_assets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  observation_id  UUID NOT NULL REFERENCES satellite_observations(id) ON DELETE CASCADE,
  asset_type      TEXT NOT NULL,
  object_key      TEXT NOT NULL,
  media_type      TEXT NOT NULL,
  width           INTEGER,
  height          INTEGER,
  bbox_min_lon    DOUBLE PRECISION NOT NULL,
  bbox_min_lat    DOUBLE PRECISION NOT NULL,
  bbox_max_lon    DOUBLE PRECISION NOT NULL,
  bbox_max_lat    DOUBLE PRECISION NOT NULL,
  crs             TEXT NOT NULL,
  nodata          DOUBLE PRECISION,
  byte_size       INTEGER NOT NULL,
  checksum        TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT satellite_assets_tamano CHECK (byte_size > 0),
  CONSTRAINT satellite_assets_bbox CHECK (
    bbox_min_lon <= bbox_max_lon AND bbox_min_lat <= bbox_max_lat
  )
);

CREATE UNIQUE INDEX satellite_assets_observation_id_asset_type_key
  ON satellite_assets (observation_id, asset_type);

CREATE INDEX satellite_assets_organization_id_idx ON satellite_assets (organization_id);

-- ---------------------------------------------------------------------------
-- RLS. Misma política que el resto del Directorio IoT y que `parcels`
-- (migración 0008): aislamiento por organización con la excepción acotada del
-- Admin de plataforma (ADR-0005). `ENABLE`, no `FORCE`: la aplicación se
-- conecta con `iot_platform_app`, que no es dueño de las tablas.
--
-- Las tres llevan `organization_id` propio aunque cuelguen de la parcela: sin
-- esa columna no hay política que escribir sin un JOIN, y una política con
-- JOIN se paga en cada consulta.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['satellite_observations', 'satellite_metrics', 'satellite_assets']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation_or_platform_admin ON %I USING (
         organization_id = NULLIF(current_setting(''app.current_org_id'', true), '''')::uuid
         OR current_setting(''app.is_platform_admin'', true)::boolean IS TRUE
       )', t
    );
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_platform_app') THEN
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO iot_platform_app', t);
    END IF;
  END LOOP;
END $$;
