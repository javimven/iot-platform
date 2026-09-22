-- Campañas agrícolas (BACKLOG.md #60, ADR-0012). Primera pieza del módulo de
-- campañas y cuaderno de campo: la campaña de una finca, sus unidades de
-- cultivo y las parcelas que ocupa cada una.
--
-- Sustituye al diseño anotado en BACKLOG.md #34 ("una campaña se asocia a una
-- Estación"), que se hizo cuando todavía no existían parcelas. La relación con
-- las estaciones sigue siendo posible a través de `gateways.parcel_id`.
--
-- SQL escrito a mano, como el resto del esquema: RLS, CHECKs, índices
-- parciales y triggers no los expresa Prisma.

-- ---------------------------------------------------------------------------
-- installations: datos de la explotación que pide el cuaderno completo.
--
-- Opcionales todos: una campaña sencilla no los necesita, y el asistente del
-- cuaderno completo solo los pregunta si faltan. Van en la finca y no en la
-- organización porque una organización (una cooperativa, una empresa de
-- servicios) puede llevar fincas de titulares distintos.
--
-- `region_code` es el código ISO 3166-2 de la comunidad autónoma (`ES-AN`,
-- `ES-VC`...): de él dependen las zonas vulnerables y las extensiones
-- autonómicas del cuaderno (ADR-0014). La lista cerrada se valida en la
-- aplicación; aquí solo la forma.
-- ---------------------------------------------------------------------------
ALTER TABLE installations
  ADD COLUMN holder_name TEXT,
  ADD COLUMN holder_nif  TEXT,
  ADD COLUMN rea_code    TEXT,
  ADD COLUMN address     TEXT,
  ADD COLUMN region_code TEXT,
  ADD CONSTRAINT installations_region_code_iso CHECK (
    region_code IS NULL OR region_code ~ '^ES-[A-Z]{2}$'
  );

-- ---------------------------------------------------------------------------
-- crops: catálogo global de cultivos (no es de ninguna organización).
--
-- El agricultor elige "Aguacate" de una lista en vez de escribirlo: así se
-- podrán mapear los códigos oficiales (EPPO, catálogo de productos del SIEX)
-- sin reescribir los datos de nadie. En el MVP los códigos van vacíos: se
-- rellenan al importar los catálogos oficiales (fase 3), nunca a ojo.
-- Lo siembra `prisma/seed.ts`, igual que los demás catálogos de plataforma.
-- ---------------------------------------------------------------------------
CREATE TABLE crops (
  id                   TEXT PRIMARY KEY,
  name                 TEXT NOT NULL,
  category             TEXT NOT NULL,
  eppo_code            TEXT,
  siex_code            TEXT,
  siex_catalog_version TEXT,
  active               BOOLEAN NOT NULL DEFAULT true,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT crops_id_es_slug CHECK (id ~ '^[a-z0-9_]+$'),
  CONSTRAINT crops_categoria CHECK (
    category IN ('woody', 'herbaceous', 'horticultural', 'forage', 'other')
  )
);

CREATE UNIQUE INDEX crops_nombre_uniq ON crops (lower(name));

-- ---------------------------------------------------------------------------
-- campaigns
--
-- Un periodo productivo de una finca ("Aguacate Hass · 2026"). El modo
-- (`simple`/`complete`) cambia la experiencia y las validaciones, no la
-- estructura: pasar de uno a otro no copia ni borra nada (ADR-0013).
--
-- Fechas `DATE` y no `TIMESTAMPTZ`: una campaña empieza "el 3 de febrero",
-- no a una hora UTC inventada.
--
-- `notebook_profile`: las respuestas del asistente del cuaderno completo
-- (¿fitosanitarios? ¿fertirrigación? ¿ecológico?...). Son configuración, no
-- datos regulados, y sus preguntas cambiarán con la normativa: JSON validado
-- en la aplicación.
-- ---------------------------------------------------------------------------
CREATE TYPE "CampaignStatus" AS ENUM ('draft', 'active', 'closed', 'archived');
CREATE TYPE "CampaignManagementMode" AS ENUM ('simple', 'complete');

CREATE TABLE campaigns (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id        UUID NOT NULL REFERENCES organizations(id),
  installation_id        UUID NOT NULL REFERENCES installations(id),
  name                   TEXT NOT NULL,
  status                 "CampaignStatus" NOT NULL DEFAULT 'active',
  management_mode        "CampaignManagementMode" NOT NULL DEFAULT 'simple',
  start_date             DATE NOT NULL,
  expected_end_date      DATE,
  end_date               DATE,
  notes                  TEXT,
  notebook_profile       JSONB NOT NULL DEFAULT '{}'::jsonb,
  declared_production_kg DOUBLE PRECISION,
  closing_notes          TEXT,
  closed_at              TIMESTAMPTZ,
  -- Quién, sin clave foránea a `users`: misma convención que `updated_by`
  -- y `audit_log.actor_user_id`.
  closed_by              UUID,
  created_by             UUID NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at             TIMESTAMPTZ,

  CONSTRAINT campaigns_nombre_no_vacio CHECK (length(btrim(name)) > 0),
  CONSTRAINT campaigns_fin_prevista CHECK (expected_end_date IS NULL OR expected_end_date >= start_date),
  CONSTRAINT campaigns_fin CHECK (end_date IS NULL OR end_date >= start_date),
  -- Cerrada = con fecha de fin y con constancia de cuándo se cerró.
  CONSTRAINT campaigns_cerrada_completa CHECK (
    status <> 'closed' OR (end_date IS NOT NULL AND closed_at IS NOT NULL)
  ),
  CONSTRAINT campaigns_perfil_es_objeto CHECK (jsonb_typeof(notebook_profile) = 'object'),
  CONSTRAINT campaigns_produccion CHECK (declared_production_kg IS NULL OR declared_production_kg >= 0)
);

CREATE INDEX campaigns_organization_id_idx ON campaigns (organization_id);
CREATE INDEX campaigns_installation_id_idx ON campaigns (installation_id);
-- El listado se lee siempre así: las vivas de una organización, por estado.
CREATE INDEX campaigns_vivas_por_estado_idx
  ON campaigns (organization_id, status, start_date)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- crop_units: unidad de cultivo (se aproxima a la Unidad Homogénea de
-- Cultivo sin obligar a nadie a conocer el término).
--
-- Mismo cultivo, variedad y manejo sobre una o varias parcelas. Una campaña
-- sencilla tiene una sola, creada en el alta; una compleja puede tener
-- varias (dos variedades, secano y regadío...).
--
-- `crop_name` va siempre, aunque haya `crop_id`: es el nombre tal como se
-- eligió, y un cuaderno de 2026 no debe cambiar si mañana se renombra el
-- catálogo. Sin `crop_id` es un cultivo que no está en el catálogo.
--
-- Los conjuntos cerrados pequeños y estables llevan CHECK; los que acabarán
-- siendo códigos de un catálogo oficial se validan en la aplicación.
-- ---------------------------------------------------------------------------
CREATE TABLE crop_units (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      UUID NOT NULL REFERENCES organizations(id),
  campaign_id          UUID NOT NULL REFERENCES campaigns(id),
  crop_id              TEXT REFERENCES crops(id),
  crop_name            TEXT NOT NULL,
  variety              TEXT,
  previous_crop        TEXT,
  water_regime         TEXT,
  growing_environment  TEXT,
  production_system    TEXT,
  area_ha              DOUBLE PRECISION,
  expected_yield_kg_ha DOUBLE PRECISION,
  notes                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at           TIMESTAMPTZ,

  CONSTRAINT crop_units_cultivo_no_vacio CHECK (length(btrim(crop_name)) > 0),
  CONSTRAINT crop_units_regimen CHECK (water_regime IS NULL OR water_regime IN ('rainfed', 'irrigated')),
  CONSTRAINT crop_units_entorno CHECK (
    growing_environment IS NULL OR growing_environment IN ('open_field', 'greenhouse', 'other')
  ),
  CONSTRAINT crop_units_sistema CHECK (
    production_system IS NULL OR production_system IN ('conventional', 'integrated', 'organic')
  ),
  CONSTRAINT crop_units_superficie CHECK (area_ha IS NULL OR area_ha > 0),
  CONSTRAINT crop_units_rendimiento CHECK (expected_yield_kg_ha IS NULL OR expected_yield_kg_ha >= 0)
);

CREATE INDEX crop_units_organization_id_idx ON crop_units (organization_id);
CREATE INDEX crop_units_campaign_id_idx ON crop_units (campaign_id);

-- ---------------------------------------------------------------------------
-- crop_unit_parcels: qué parcelas ocupa cada unidad, y cuánto de cada una.
--
-- `area_ha` nulo = la parcela entera. No se asume que la superficie cultivada
-- sea siempre la de la parcela: medio campo de tomate y medio en barbecho es
-- corriente.
--
-- Clave compuesta y borrado físico: es una relación, no un registro con
-- historia. Lo que sí tiene historia (las actividades) apunta aquí con clave
-- foránea, así que una parcela con actividades registradas no se puede quitar
-- de la unidad sin más (migración 0011).
-- ---------------------------------------------------------------------------
CREATE TABLE crop_unit_parcels (
  crop_unit_id    UUID NOT NULL REFERENCES crop_units(id),
  parcel_id       UUID NOT NULL REFERENCES parcels(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  area_ha         DOUBLE PRECISION,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (crop_unit_id, parcel_id),
  CONSTRAINT crop_unit_parcels_superficie CHECK (area_ha IS NULL OR area_ha > 0)
);

CREATE INDEX crop_unit_parcels_organization_id_idx ON crop_unit_parcels (organization_id);
CREATE INDEX crop_unit_parcels_parcel_id_idx ON crop_unit_parcels (parcel_id);

-- Integridad que una clave foránea no expresa, igual que la de estación y
-- parcela (migración 0008): la parcela tiene que ser de la misma organización
-- Y de la misma finca que la campaña. Sin esto, un `parcelId` de otra finca
-- (u otra organización: las comprobaciones de clave foránea no pasan por RLS)
-- colado en una petición pasaría sin problema.
CREATE OR REPLACE FUNCTION check_crop_unit_parcel_matches_campaign()
RETURNS TRIGGER AS $$
DECLARE
  campana_organizacion UUID;
  campana_finca        UUID;
  parcela_organizacion UUID;
  parcela_finca        UUID;
BEGIN
  SELECT c.organization_id, c.installation_id
    INTO campana_organizacion, campana_finca
    FROM crop_units u JOIN campaigns c ON c.id = u.campaign_id
   WHERE u.id = NEW.crop_unit_id;

  SELECT organization_id, installation_id
    INTO parcela_organizacion, parcela_finca
    FROM parcels WHERE id = NEW.parcel_id;

  IF parcela_organizacion IS DISTINCT FROM campana_organizacion
     OR NEW.organization_id IS DISTINCT FROM campana_organizacion THEN
    RAISE EXCEPTION 'crop_unit_parcels: parcel % and crop unit % must belong to the same organization',
      NEW.parcel_id, NEW.crop_unit_id;
  END IF;

  IF parcela_finca IS DISTINCT FROM campana_finca THEN
    RAISE EXCEPTION 'crop_unit_parcels: parcel % (installation %) must belong to the campaign installation %',
      NEW.parcel_id, parcela_finca, campana_finca;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER crop_unit_parcel_matches_campaign
  BEFORE INSERT OR UPDATE ON crop_unit_parcels
  FOR EACH ROW EXECUTE FUNCTION check_crop_unit_parcel_matches_campaign();

-- La unidad de cultivo, de la misma organización que su campaña.
CREATE OR REPLACE FUNCTION check_crop_unit_matches_campaign()
RETURNS TRIGGER AS $$
DECLARE
  campana_organizacion UUID;
BEGIN
  SELECT organization_id INTO campana_organizacion FROM campaigns WHERE id = NEW.campaign_id;
  IF campana_organizacion IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'crop_units: crop unit organization % must match campaign organization %',
      NEW.organization_id, campana_organizacion;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER crop_unit_matches_campaign
  BEFORE INSERT OR UPDATE OF campaign_id, organization_id ON crop_units
  FOR EACH ROW EXECUTE FUNCTION check_crop_unit_matches_campaign();

-- La campaña, de una finca de su propia organización.
CREATE OR REPLACE FUNCTION check_campaign_matches_installation()
RETURNS TRIGGER AS $$
DECLARE
  finca_organizacion UUID;
BEGIN
  SELECT organization_id INTO finca_organizacion FROM installations WHERE id = NEW.installation_id;
  IF finca_organizacion IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'campaigns: installation % does not belong to organization %',
      NEW.installation_id, NEW.organization_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campaign_matches_installation
  BEFORE INSERT OR UPDATE OF installation_id, organization_id ON campaigns
  FOR EACH ROW EXECUTE FUNCTION check_campaign_matches_installation();

-- ---------------------------------------------------------------------------
-- RLS (DATA_MODEL.md §7). Misma política que el resto de tablas de
-- organización (migraciones 0002, 0008, 0009). `crops` no la lleva: es un
-- catálogo de plataforma, igual que `channel_types` o `features`.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['campaigns', 'crop_units', 'crop_unit_parcels']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation_or_platform_admin ON %I USING (
         organization_id = NULLIF(current_setting(''app.current_org_id'', true), '''')::uuid
         OR current_setting(''app.is_platform_admin'', true)::boolean IS TRUE
       )', t
    );
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_platform_app') THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON campaigns, crop_units, crop_unit_parcels TO iot_platform_app';
    EXECUTE 'GRANT SELECT ON crops TO iot_platform_app';
  END IF;
END $$;
