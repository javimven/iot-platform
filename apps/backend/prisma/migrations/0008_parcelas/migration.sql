-- Parcelas (BACKLOG.md #36, ADR-0009). Primera pieza del modulo de satelite:
-- el recinto real de cultivo, dibujado por el usuario, del que se calcularan
-- las observaciones de Sentinel-2. Hasta ahora lo unico geografico de la
-- plataforma era el punto `latitude`/`longitude` de la finca.
--
-- Migracion SQL escrita a mano (mismo criterio que 0002 con RLS y 0003 con el
-- particionado): Prisma no expresa tipos de PostGIS, ni indices GiST, ni
-- triggers, ni politicas de RLS.

-- ---------------------------------------------------------------------------
-- PostGIS. Comprobado el 2026-09-21 contra la base gestionada real de
-- DigitalOcean: `postgis` 3.5.7 disponible (sin instalar) sobre PostgreSQL
-- 16.15. Esta migracion corre con `DATABASE_URL_MIGRATE` (usuario admin del
-- proveedor, infra/docker/deploy.sh), que es quien puede crear extensiones;
-- el rol de la aplicacion no las necesita para usar los tipos.
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;

-- ---------------------------------------------------------------------------
-- parcels
--
-- `geometry(MultiPolygon, 4326)` aunque la v1 solo deje dibujar un recinto:
-- una parcela partida por un camino es corriente y admitirla hoy no cuesta
-- nada; la aplicacion normaliza un Polygon de entrada a MultiPolygon.
-- 4326 (WGS84, grados) es lo que hablan GeoJSON y las APIs de Copernicus, y
-- lo que ya usaban `installations.latitude/longitude`.
--
-- `area_m2` y la caja envolvente van desnormalizados a proposito: se calculan
-- una vez al guardar (ST_Area sobre geography, ST_Envelope) y se leen en cada
-- listado sin tocar la geometria, que es la columna pesada.
-- ---------------------------------------------------------------------------
CREATE TABLE parcels (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL REFERENCES organizations(id),
  installation_id  UUID NOT NULL REFERENCES installations(id),
  name             TEXT NOT NULL,
  geometry         geometry(MultiPolygon, 4326) NOT NULL,
  area_m2          DOUBLE PRECISION NOT NULL,
  bbox_min_lon     DOUBLE PRECISION NOT NULL,
  bbox_min_lat     DOUBLE PRECISION NOT NULL,
  bbox_max_lon     DOUBLE PRECISION NOT NULL,
  bbox_max_lat     DOUBLE PRECISION NOT NULL,
  geometry_version INTEGER NOT NULL DEFAULT 1,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at       TIMESTAMPTZ,

  CONSTRAINT parcels_area_positiva CHECK (area_m2 > 0),
  CONSTRAINT parcels_bbox_coherente CHECK (
    bbox_min_lon <= bbox_max_lon AND bbox_min_lat <= bbox_max_lat
    AND bbox_min_lon >= -180 AND bbox_max_lon <= 180
    AND bbox_min_lat >= -90 AND bbox_max_lat <= 90
  )
);

CREATE INDEX parcels_organization_id_idx ON parcels (organization_id);
CREATE INDEX parcels_installation_id_idx ON parcels (installation_id);

-- Indice espacial: hoy no hay ninguna consulta que lo necesite (se lee por
-- finca), pero es lo que hara baratas las preguntas que vendran solas en
-- cuanto existan parcelas —"que parcela contiene esta estacion", "que
-- parcelas toca este tile"— y crearlo despues sobre una tabla con datos es
-- mas caro que crearlo vacio.
CREATE INDEX parcels_geometry_gist ON parcels USING GIST (geometry);

-- Dos parcelas de la misma finca no deberian llamarse igual: el usuario las
-- elige por nombre en un desplegable. Parcial, para que el borrado logico
-- libere el nombre.
CREATE UNIQUE INDEX parcels_nombre_por_finca_uniq
  ON parcels (installation_id, name)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- gateways.parcel_id
--
-- Opcional por diseno (BACKLOG.md #36): una estacion puede no tener parcela
-- —todas las actuales— y una parcela puede no tener estacion. Una estacion
-- pertenece como mucho a una parcela; una parcela puede tener varias.
-- ---------------------------------------------------------------------------
ALTER TABLE gateways ADD COLUMN parcel_id UUID REFERENCES parcels(id);
CREATE INDEX gateways_parcel_id_idx ON gateways (parcel_id);

-- Integridad que una clave foranea no puede expresar, igual que el trigger
-- Zona<->Gateway de la migracion 0002: la parcela tiene que ser de la misma
-- organizacion Y de la misma finca que la estacion. Sin esto, un `parcelId`
-- de otra organizacion colado en un PATCH pasaria la FK sin problema.
CREATE OR REPLACE FUNCTION check_gateway_parcel_matches_installation()
RETURNS TRIGGER AS $$
DECLARE
  parcel_installation_id UUID;
  parcel_organization_id UUID;
BEGIN
  IF NEW.parcel_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT installation_id, organization_id
    INTO parcel_installation_id, parcel_organization_id
    FROM parcels WHERE id = NEW.parcel_id;

  IF parcel_organization_id IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'gateway.parcel_id (organization %) must belong to the same organization as the gateway (organization %)',
      parcel_organization_id, NEW.organization_id;
  END IF;

  IF parcel_installation_id IS DISTINCT FROM NEW.installation_id THEN
    RAISE EXCEPTION 'gateway.parcel_id (installation %) must belong to the same installation as the gateway (installation %)',
      parcel_installation_id, NEW.installation_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER gateway_parcel_matches_installation
  BEFORE INSERT OR UPDATE OF parcel_id, installation_id, organization_id ON gateways
  FOR EACH ROW EXECUTE FUNCTION check_gateway_parcel_matches_installation();

-- ---------------------------------------------------------------------------
-- RLS (DATA_MODEL.md §7). Misma politica que el resto del Directorio IoT
-- (migracion 0002): aislamiento por organizacion con la excepcion acotada y
-- auditada del Admin de plataforma (ADR-0005). `ENABLE`, no `FORCE`: la
-- aplicacion se conecta con `iot_platform_app`, que no es dueno de la tabla.
-- ---------------------------------------------------------------------------
ALTER TABLE parcels ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_or_platform_admin ON parcels USING (
  organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
  OR current_setting('app.is_platform_admin', true)::boolean IS TRUE
);

-- El rol de la aplicacion no existe en todos los entornos (en local lo crea
-- infra/docker/postgres-init/01-app-role.sql, y en gestionado lo concede
-- 02-grant-app-role-managed.sql en cada despliegue); sin el, el GRANT
-- rompería la migracion. Mismo patron que la migracion 0006.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_platform_app') THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON parcels TO iot_platform_app';
  END IF;
END $$;
