-- Cuaderno de campo: actividades de campaña (BACKLOG.md #60, ADR-0012).
--
-- El agricultor no "rellena un cuaderno": registra lo que ha hecho (un riego,
-- un tratamiento, una cosecha) y el cuaderno se construye a partir de eso.
-- Cada cosa que hace es una fila de `campaign_activities`, común a todos los
-- tipos, con un detalle tipado según el tipo.
--
-- Por qué tablas de detalle y no un JSON: los datos del cuaderno son los que
-- se exportarán al CUE y los que se piden en una inspección (dosis, número de
-- registro, superficie tratada...). Tienen que validarse y consultarse, y un
-- JSON gigante no deja ninguna de las dos cosas. Por qué no una tabla por cada
-- apartado del cuaderno oficial: sería una treintena para empezar. Aquí hay
-- cinco, una por tipo regulado del MVP, más los productos de cada tratamiento.
--
-- Campos alineados con el Anexo V del SIEX 3.11 (bloques 5, 8, 9, 10 y 11 del
-- CUE) y con el Reglamento de Ejecución (UE) 2023/564, pero con nombres
-- propios: la traducción al formato oficial es cosa de un mapeador aparte
-- (ADR-0014), no del modelo.

-- ---------------------------------------------------------------------------
-- notebook_people: quién trata y quién asesora, dado de alta una vez.
--
-- Personas propias, empresas de servicios y asesores, con su NIF y su
-- inscripción en el ROPO. Se eligen de una lista al registrar un tratamiento
-- en vez de teclearlos cada vez. `installation_id` nulo = sirve para todas
-- las fincas de la organización.
--
-- Nombre y apellidos por separado, y razón social aparte: así los pide el
-- CUE (bloque 8, "Identificación del aplicador").
-- ---------------------------------------------------------------------------
CREATE TABLE notebook_people (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  installation_id UUID REFERENCES installations(id),
  kind            TEXT NOT NULL,
  first_name      TEXT,
  surname_1       TEXT,
  surname_2       TEXT,
  company_name    TEXT,
  nif             TEXT,
  ropo_number     TEXT,
  ropo_card_type  TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,

  CONSTRAINT notebook_people_tipo CHECK (kind IN ('own_staff', 'service_company', 'adviser')),
  -- O una persona con nombre, o una empresa con razón social.
  CONSTRAINT notebook_people_identificado CHECK (
    length(btrim(coalesce(first_name, ''))) > 0 OR length(btrim(coalesce(company_name, ''))) > 0
  )
);

CREATE INDEX notebook_people_organization_id_idx ON notebook_people (organization_id);

-- ---------------------------------------------------------------------------
-- notebook_equipment: equipos de tratamiento y aplicación, igual que las
-- personas: se dan de alta una vez y se eligen después.
-- ---------------------------------------------------------------------------
CREATE TABLE notebook_equipment (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    UUID NOT NULL REFERENCES organizations(id),
  installation_id    UUID REFERENCES installations(id),
  description        TEXT NOT NULL,
  brand              TEXT,
  model              TEXT,
  roma_number        TEXT,
  acquired_on        DATE,
  last_inspection_on DATE,
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ,

  CONSTRAINT notebook_equipment_descripcion CHECK (length(btrim(description)) > 0)
);

CREATE INDEX notebook_equipment_organization_id_idx ON notebook_equipment (organization_id);

-- ---------------------------------------------------------------------------
-- campaign_activities: lo que se ha hecho, común a todos los tipos.
--
-- **Fecha de inicio y de fin, siempre**, como en todos los bloques del CUE.
-- Un riego de un día tiene las dos iguales; una fertirrigación de la primera
-- quincena de agosto va en un solo registro (lo admite el RD 1051/2022 para
-- cultivos intensivos y fertirrigación). `DATE`, sin hora inventada: la hora
-- es opcional y solo tiene sentido en los tratamientos.
--
-- `type` es TEXT con CHECK y no un enum: van a llegar tipos nuevos (semilla
-- tratada, postcosecha, análisis...) y un CHECK se cambia sin las pegas de
-- `ALTER TYPE ... ADD VALUE` (migración 0007).
--
-- `origin`: cómo nació el registro. `repeated` = copiado de otro con
-- "Repetir" (y confirmado); `sensor_suggestion` queda reservado para cuando
-- se proponga un riego a partir de la telemetría: un dato de un sensor nunca
-- se convierte solo en un registro del cuaderno, siempre lo confirma alguien.
-- ---------------------------------------------------------------------------
CREATE TABLE campaign_activities (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL REFERENCES organizations(id),
  campaign_id      UUID NOT NULL REFERENCES campaigns(id),
  type             TEXT NOT NULL,
  start_date       DATE NOT NULL,
  end_date         DATE NOT NULL,
  start_time       TEXT,
  notes            TEXT,
  origin           TEXT NOT NULL DEFAULT 'manual',
  repeated_from_id UUID REFERENCES campaign_activities(id),
  created_by       UUID NOT NULL,
  updated_by       UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at       TIMESTAMPTZ,
  deleted_by       UUID,
  delete_reason    TEXT,

  CONSTRAINT campaign_activities_tipo CHECK (type IN (
    'irrigation', 'fertilization', 'phytosanitary', 'field_work',
    'harvest', 'observation', 'sowing', 'other'
  )),
  CONSTRAINT campaign_activities_fechas CHECK (end_date >= start_date),
  CONSTRAINT campaign_activities_hora CHECK (start_time IS NULL OR start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  CONSTRAINT campaign_activities_origen CHECK (origin IN ('manual', 'repeated', 'sensor_suggestion')),
  CONSTRAINT campaign_activities_repetida CHECK ((origin = 'repeated') = (repeated_from_id IS NOT NULL))
);

CREATE INDEX campaign_activities_organization_id_idx ON campaign_activities (organization_id);
-- La línea de tiempo de una campaña: las vivas, de la más reciente hacia atrás.
CREATE INDEX campaign_activities_linea_de_tiempo_idx
  ON campaign_activities (campaign_id, start_date DESC, created_at DESC)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- activity_targets: sobre qué parcelas se hizo, y cuánta superficie de cada
-- una. Una actividad sobre tres parcelas es UN registro con tres destinos, no
-- tres registros: el usuario marca tres casillas y la trazabilidad por
-- parcela queda igual.
--
-- La clave foránea compuesta a `crop_unit_parcels` garantiza que la parcela es
-- de esa unidad de cultivo, y de paso impide quitar de la unidad una parcela
-- con actividades registradas.
--
-- `area_ha` nulo = toda la superficie de esa parcela en la unidad.
-- ---------------------------------------------------------------------------
CREATE TABLE activity_targets (
  activity_id     UUID NOT NULL REFERENCES campaign_activities(id) ON DELETE CASCADE,
  crop_unit_id    UUID NOT NULL,
  parcel_id       UUID NOT NULL,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  area_ha         DOUBLE PRECISION,

  PRIMARY KEY (activity_id, crop_unit_id, parcel_id),
  FOREIGN KEY (crop_unit_id, parcel_id) REFERENCES crop_unit_parcels (crop_unit_id, parcel_id),
  CONSTRAINT activity_targets_superficie CHECK (area_ha IS NULL OR area_ha > 0)
);

CREATE INDEX activity_targets_organization_id_idx ON activity_targets (organization_id);
CREATE INDEX activity_targets_parcel_id_idx ON activity_targets (parcel_id);

-- La unidad de cultivo del destino tiene que ser de la misma campaña que la
-- actividad (la clave compuesta ya asegura que la parcela es de la unidad).
CREATE OR REPLACE FUNCTION check_activity_target_matches_campaign()
RETURNS TRIGGER AS $$
DECLARE
  campana_actividad UUID;
  organizacion_actividad UUID;
  campana_unidad UUID;
BEGIN
  SELECT campaign_id, organization_id INTO campana_actividad, organizacion_actividad
    FROM campaign_activities WHERE id = NEW.activity_id;
  SELECT campaign_id INTO campana_unidad FROM crop_units WHERE id = NEW.crop_unit_id;

  IF campana_unidad IS DISTINCT FROM campana_actividad
     OR NEW.organization_id IS DISTINCT FROM organizacion_actividad THEN
    RAISE EXCEPTION 'activity_targets: crop unit % is not part of the campaign of activity %',
      NEW.crop_unit_id, NEW.activity_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER activity_target_matches_campaign
  BEFORE INSERT OR UPDATE ON activity_targets
  FOR EACH ROW EXECUTE FUNCTION check_activity_target_matches_campaign();

-- ---------------------------------------------------------------------------
-- Detalles por tipo. Una fila por actividad (la clave primaria es la propia
-- actividad). Todo opcional en la base: qué es obligatorio depende del modo de
-- la campaña (sencillo o completo) y de la normativa aplicable, y eso se
-- decide en la aplicación con reglas versionadas (ADR-0013), no aquí.
--
-- Cantidades: lo que el usuario escribió (valor + unidad) y, al lado, el valor
-- normalizado que calcula el backend para los resúmenes (m³ totales, kg,
-- kg de N por hectárea). Nunca se suman valores de unidades distintas.
--
-- Los campos que acabarán siendo códigos de un catálogo oficial (sistema de
-- riego, tipo de material, método de aplicación...) son TEXT validado en la
-- aplicación: cuando entren los catálogos del SIEX, se mapean sin migración.
-- ---------------------------------------------------------------------------

-- Riego (CUE bloque 10).
CREATE TABLE irrigation_details (
  activity_id     UUID PRIMARY KEY REFERENCES campaign_activities(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  system          TEXT,
  amount          DOUBLE PRECISION,
  amount_unit     TEXT,
  volume_m3       DOUBLE PRECISION,
  water_source    TEXT,
  meter_number    TEXT,
  -- Calidad del agua, cuando se fertirriga (CUE bloque 9, "Información del
  -- agua"): van con el riego porque son del agua, no del abono.
  nitrate_mg_l    DOUBLE PRECISION,
  p2o5_mg_l       DOUBLE PRECISION,

  CONSTRAINT irrigation_details_cantidad CHECK (
    (amount IS NULL) = (amount_unit IS NULL) AND (amount IS NULL OR amount >= 0)
  ),
  CONSTRAINT irrigation_details_unidad CHECK (amount_unit IS NULL OR amount_unit IN ('m3', 'm3_ha', 'l')),
  CONSTRAINT irrigation_details_volumen CHECK (volume_m3 IS NULL OR volume_m3 >= 0),
  CONSTRAINT irrigation_details_agua CHECK (
    (nitrate_mg_l IS NULL OR nitrate_mg_l >= 0) AND (p2o5_mg_l IS NULL OR p2o5_mg_l >= 0)
  )
);

-- Fertilización (CUE bloque 9, RD 1051/2022 art. 5).
CREATE TABLE fertilization_details (
  activity_id         UUID PRIMARY KEY REFERENCES campaign_activities(id) ON DELETE CASCADE,
  organization_id     UUID NOT NULL REFERENCES organizations(id),
  fertilization_type  TEXT,
  material_type       TEXT,
  product_name        TEXT,
  dose                DOUBLE PRECISION,
  dose_unit           TEXT,
  application_method  TEXT,
  n_pct               DOUBLE PRECISION,
  p2o5_pct            DOUBLE PRECISION,
  k2o_pct             DOUBLE PRECISION,
  organic_matter_pct  DOUBLE PRECISION,
  -- Normalizados por el backend a partir de dosis y riqueza, solo cuando las
  -- unidades lo permiten (una dosis en litros sin densidad no da kg de N).
  n_kg_ha             DOUBLE PRECISION,
  p2o5_kg_ha          DOUBLE PRECISION,
  k2o_kg_ha           DOUBLE PRECISION,
  supplier_name       TEXT,
  supplier_nif        TEXT,
  supplier_rega       TEXT,
  supplier_nima       TEXT,
  applicator_company  TEXT,
  regfer_code         TEXT,
  equipment_id        UUID REFERENCES notebook_equipment(id),
  -- Copia del equipo tal como era al registrarlo: si mañana cambia su ficha,
  -- el cuaderno de hoy no cambia.
  equipment_snapshot  JSONB,

  CONSTRAINT fertilization_details_dosis CHECK (
    (dose IS NULL) = (dose_unit IS NULL) AND (dose IS NULL OR dose >= 0)
  ),
  CONSTRAINT fertilization_details_unidad CHECK (
    dose_unit IS NULL OR dose_unit IN ('kg_ha', 'l_ha', 't_ha', 'm3_ha', 'kg', 'l', 't', 'm3')
  ),
  CONSTRAINT fertilization_details_riquezas CHECK (
    (n_pct IS NULL OR n_pct BETWEEN 0 AND 100) AND
    (p2o5_pct IS NULL OR p2o5_pct BETWEEN 0 AND 100) AND
    (k2o_pct IS NULL OR k2o_pct BETWEEN 0 AND 100) AND
    (organic_matter_pct IS NULL OR organic_matter_pct BETWEEN 0 AND 100)
  ),
  CONSTRAINT fertilization_details_nutrientes CHECK (
    (n_kg_ha IS NULL OR n_kg_ha >= 0) AND (p2o5_kg_ha IS NULL OR p2o5_kg_ha >= 0) AND
    (k2o_kg_ha IS NULL OR k2o_kg_ha >= 0)
  )
);

-- Tratamiento fitosanitario (CUE bloque 8, Reglamento (UE) 2023/564).
CREATE TABLE phytosanitary_details (
  activity_id              UUID PRIMARY KEY REFERENCES campaign_activities(id) ON DELETE CASCADE,
  organization_id          UUID NOT NULL REFERENCES organizations(id),
  problem                  TEXT,
  problem_category         TEXT,
  justification            TEXT,
  -- Estado fenológico: el código BBCH por dentro, el nombre que vio el
  -- agricultor por fuera ("Floración").
  bbch_code                TEXT,
  phenological_stage_label TEXT,
  applicator_id            UUID REFERENCES notebook_people(id),
  applicator_snapshot      JSONB,
  adviser_id               UUID REFERENCES notebook_people(id),
  adviser_snapshot         JSONB,
  equipment_id             UUID REFERENCES notebook_equipment(id),
  equipment_snapshot       JSONB,
  manual_application       BOOLEAN,
  efficacy                 TEXT,

  CONSTRAINT phytosanitary_details_categoria CHECK (
    problem_category IS NULL OR problem_category IN (
      'weeds', 'diseases', 'arthropods', 'growth_regulators', 'other'
    )
  ),
  CONSTRAINT phytosanitary_details_eficacia CHECK (efficacy IS NULL OR efficacy IN ('good', 'fair', 'poor')),
  CONSTRAINT phytosanitary_details_bbch CHECK (bbch_code IS NULL OR bbch_code ~ '^[0-9]{2}$')
);

-- Productos de un tratamiento: puede ser una mezcla de varios en el mismo
-- depósito, y cada uno tiene su número de registro y su dosis.
--
-- `source`: de dónde salieron los datos del producto. Hoy siempre `manual`;
-- cuando se consulte el Registro de Productos Fitosanitarios del MAPA (fase
-- 3), `mapa_registry` con la fecha de la consulta, para distinguir el estado
-- del producto el día del tratamiento del estado de hoy.
CREATE TABLE phytosanitary_products (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL REFERENCES organizations(id),
  activity_id         UUID NOT NULL REFERENCES campaign_activities(id) ON DELETE CASCADE,
  position            SMALLINT NOT NULL DEFAULT 0,
  product_name        TEXT NOT NULL,
  registry_number     TEXT,
  active_substances   TEXT,
  dose                DOUBLE PRECISION,
  dose_unit           TEXT,
  total_quantity      DOUBLE PRECISION,
  total_quantity_unit TEXT,
  source              TEXT NOT NULL DEFAULT 'manual',
  source_updated_at   TIMESTAMPTZ,

  CONSTRAINT phytosanitary_products_nombre CHECK (length(btrim(product_name)) > 0),
  CONSTRAINT phytosanitary_products_dosis CHECK (
    (dose IS NULL) = (dose_unit IS NULL) AND (dose IS NULL OR dose >= 0)
  ),
  -- kg o l por hectárea es lo que pide el Reglamento (UE) 2023/564; por
  -- hectolitro es como se lee en muchas etiquetas, y se admite también.
  CONSTRAINT phytosanitary_products_unidad CHECK (
    dose_unit IS NULL OR dose_unit IN ('l_ha', 'kg_ha', 'l_hl', 'kg_hl')
  ),
  CONSTRAINT phytosanitary_products_total CHECK (
    (total_quantity IS NULL) = (total_quantity_unit IS NULL)
    AND (total_quantity IS NULL OR total_quantity >= 0)
    AND (total_quantity_unit IS NULL OR total_quantity_unit IN ('l', 'kg'))
  ),
  CONSTRAINT phytosanitary_products_fuente CHECK (source IN ('manual', 'mapa_registry'))
);

CREATE INDEX phytosanitary_products_activity_id_idx ON phytosanitary_products (activity_id);
CREATE INDEX phytosanitary_products_organization_id_idx ON phytosanitary_products (organization_id);

-- Cosecha, recolección o siega (CUE bloque 11).
CREATE TABLE harvest_details (
  activity_id      UUID PRIMARY KEY REFERENCES campaign_activities(id) ON DELETE CASCADE,
  organization_id  UUID NOT NULL REFERENCES organizations(id),
  product          TEXT,
  quantity         DOUBLE PRECISION,
  quantity_unit    TEXT,
  -- En kg, para sumar y sacar el rendimiento. Nulo si se contó en unidades.
  quantity_kg      DOUBLE PRECISION,
  lot_code         TEXT,
  delivery_note    TEXT,
  customer_name    TEXT,
  customer_nif     TEXT,
  customer_address TEXT,
  customer_rgseaa  TEXT,
  destination      TEXT,
  quality_grade    TEXT,

  CONSTRAINT harvest_details_cantidad CHECK (
    (quantity IS NULL) = (quantity_unit IS NULL) AND (quantity IS NULL OR quantity >= 0)
  ),
  CONSTRAINT harvest_details_unidad CHECK (quantity_unit IS NULL OR quantity_unit IN ('kg', 't', 'units')),
  CONSTRAINT harvest_details_kg CHECK (quantity_kg IS NULL OR quantity_kg >= 0)
);

-- Labores (CUE bloque 5): poda, siega, laboreo, desbroce...
CREATE TABLE field_work_details (
  activity_id            UUID PRIMARY KEY REFERENCES campaign_activities(id) ON DELETE CASCADE,
  organization_id        UUID NOT NULL REFERENCES organizations(id),
  work_type              TEXT NOT NULL,
  -- "Depositado en el suelo de los restos de poda / desbrozados (S/N)": el
  -- CUE los pide, y son un sí o un no.
  pruning_residues_left  BOOLEAN,
  clearing_residues_left BOOLEAN,
  hours                  DOUBLE PRECISION,
  machinery              TEXT,

  CONSTRAINT field_work_details_horas CHECK (hours IS NULL OR hours >= 0)
);

-- ---------------------------------------------------------------------------
-- La historia de una campaña cerrada no se toca.
--
-- Al cerrar una campaña su cuaderno queda como estaba. Si hay que corregir
-- algo, se reabre (queda en la auditoría, con el motivo) y se vuelve a
-- cerrar. La aplicación ya lo impide; esto es la red de seguridad por si un
-- día un camino de código se olvida de comprobarlo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_campaign_open(campana UUID)
RETURNS VOID AS $$
DECLARE
  estado "CampaignStatus";
BEGIN
  SELECT status INTO estado FROM campaigns WHERE id = campana;
  IF estado IN ('closed', 'archived') THEN
    RAISE EXCEPTION 'campaign % is %: its notebook cannot be modified without reopening it', campana, estado;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_activity_campaign_open()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM check_campaign_open(OLD.campaign_id);
    RETURN OLD;
  END IF;
  PERFORM check_campaign_open(NEW.campaign_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER activity_campaign_open
  BEFORE INSERT OR UPDATE OR DELETE ON campaign_activities
  FOR EACH ROW EXECUTE FUNCTION check_activity_campaign_open();

-- Lo mismo para todo lo que cuelga de una actividad.
CREATE OR REPLACE FUNCTION check_activity_child_campaign_open()
RETURNS TRIGGER AS $$
DECLARE
  campana UUID;
BEGIN
  SELECT campaign_id INTO campana FROM campaign_activities
   WHERE id = (CASE WHEN TG_OP = 'DELETE' THEN OLD.activity_id ELSE NEW.activity_id END);
  PERFORM check_campaign_open(campana);
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'activity_targets', 'irrigation_details', 'fertilization_details',
    'phytosanitary_details', 'phytosanitary_products', 'harvest_details', 'field_work_details'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON %I
         FOR EACH ROW EXECUTE FUNCTION check_activity_child_campaign_open()',
      t || '_campaign_open', t
    );
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- RLS: misma política que el resto de tablas de organización. Todas llevan
-- `organization_id` propio aunque cuelguen de otra: una política con JOIN se
-- paga en cada consulta (migración 0009).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'notebook_people', 'notebook_equipment', 'campaign_activities', 'activity_targets',
    'irrigation_details', 'fertilization_details', 'phytosanitary_details',
    'phytosanitary_products', 'harvest_details', 'field_work_details'
  ]
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
