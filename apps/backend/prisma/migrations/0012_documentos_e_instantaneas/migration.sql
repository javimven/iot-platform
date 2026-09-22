-- Documentos del cuaderno e instantáneas de campañas cerradas (BACKLOG.md
-- #60, ADR-0012).

-- ---------------------------------------------------------------------------
-- documents: un fichero guardado en el almacenamiento de objetos.
--
-- Genérico a propósito: hoy lo usan las campañas (facturas, analíticas,
-- albaranes, fotos de una plaga), pero una factura de fitosanitarios o el
-- certificado de inspección de un equipo no son "de una campaña". Dónde se
-- usa cada uno lo dice `document_links`.
--
-- **Un fichero se guarda una sola vez**: si alguien sube dos veces la misma
-- factura (mismo SHA-256) en la misma organización, se reutiliza el documento
-- y solo se añade el vínculo nuevo. Índice único parcial para que el borrado
-- lógico libere el hueco.
--
-- El objeto va al mismo bucket privado que el satélite, a través del mismo
-- `StorageService`: nunca dos implementaciones de S3. Al cliente solo se le da
-- una URL firmada que caduca.
-- ---------------------------------------------------------------------------
CREATE TABLE documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  installation_id UUID REFERENCES installations(id),
  document_type   TEXT NOT NULL,
  title           TEXT,
  filename        TEXT NOT NULL,
  media_type      TEXT NOT NULL,
  byte_size       INTEGER NOT NULL,
  checksum        TEXT NOT NULL,
  object_key      TEXT NOT NULL UNIQUE,
  uploaded_by     UUID NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  deleted_by      UUID,

  CONSTRAINT documents_tipo CHECK (document_type IN (
    'photo', 'invoice', 'contract', 'inspection_certificate', 'container_management',
    'analysis', 'advice', 'delivery_note', 'fertilization_plan', 'other'
  )),
  CONSTRAINT documents_tamano CHECK (byte_size > 0),
  CONSTRAINT documents_checksum_sha256 CHECK (checksum ~ '^[0-9a-f]{64}$'),
  CONSTRAINT documents_nombre CHECK (length(btrim(filename)) > 0)
);

CREATE INDEX documents_organization_id_idx ON documents (organization_id);
CREATE UNIQUE INDEX documents_mismo_fichero_uniq
  ON documents (organization_id, checksum)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- document_links: dónde se usa cada documento.
--
-- Una columna con clave foránea por cada cosa a la que se puede vincular, y un
-- CHECK para que haya exactamente una. Mejor que un `target_type` + `target_id`
-- sueltos: así la base garantiza que el destino existe. Añadir un destino
-- nuevo es una columna más.
-- ---------------------------------------------------------------------------
CREATE TABLE document_links (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  document_id     UUID NOT NULL REFERENCES documents(id),
  campaign_id     UUID REFERENCES campaigns(id),
  activity_id     UUID REFERENCES campaign_activities(id),
  equipment_id    UUID REFERENCES notebook_equipment(id),
  person_id       UUID REFERENCES notebook_people(id),
  created_by      UUID NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT document_links_un_destino CHECK (
    num_nonnulls(campaign_id, activity_id, equipment_id, person_id) = 1
  )
);

CREATE INDEX document_links_organization_id_idx ON document_links (organization_id);
CREATE INDEX document_links_document_id_idx ON document_links (document_id);
CREATE UNIQUE INDEX document_links_campana_uniq ON document_links (document_id, campaign_id) WHERE campaign_id IS NOT NULL;
CREATE UNIQUE INDEX document_links_actividad_uniq ON document_links (document_id, activity_id) WHERE activity_id IS NOT NULL;
CREATE UNIQUE INDEX document_links_equipo_uniq ON document_links (document_id, equipment_id) WHERE equipment_id IS NOT NULL;
CREATE UNIQUE INDEX document_links_persona_uniq ON document_links (document_id, person_id) WHERE person_id IS NOT NULL;
CREATE INDEX document_links_campaign_id_idx ON document_links (campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX document_links_activity_id_idx ON document_links (activity_id) WHERE activity_id IS NOT NULL;

-- El documento y su destino, de la misma organización que el vínculo (las
-- claves foráneas no pasan por RLS).
CREATE OR REPLACE FUNCTION check_document_link_same_organization()
RETURNS TRIGGER AS $$
DECLARE
  org_documento UUID;
  org_destino   UUID;
BEGIN
  SELECT organization_id INTO org_documento FROM documents WHERE id = NEW.document_id;

  IF NEW.campaign_id IS NOT NULL THEN
    SELECT organization_id INTO org_destino FROM campaigns WHERE id = NEW.campaign_id;
  ELSIF NEW.activity_id IS NOT NULL THEN
    SELECT organization_id INTO org_destino FROM campaign_activities WHERE id = NEW.activity_id;
  ELSIF NEW.equipment_id IS NOT NULL THEN
    SELECT organization_id INTO org_destino FROM notebook_equipment WHERE id = NEW.equipment_id;
  ELSE
    SELECT organization_id INTO org_destino FROM notebook_people WHERE id = NEW.person_id;
  END IF;

  IF org_documento IS DISTINCT FROM NEW.organization_id OR org_destino IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'document_links: document %, its target and the link must belong to the same organization',
      NEW.document_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER document_link_same_organization
  BEFORE INSERT OR UPDATE ON document_links
  FOR EACH ROW EXECUTE FUNCTION check_document_link_same_organization();

-- ---------------------------------------------------------------------------
-- campaign_snapshots: cómo era todo al cerrar la campaña.
--
-- Si dentro de dos años cambia el titular, la dirección, el asesor o el
-- contorno de una parcela, el cuaderno cerrado de 2026 no puede cambiar con
-- ellos. Al cerrar se copia aquí lo que no es de la campaña pero la describe
-- (titular, finca, parcelas y superficies, unidades de cultivo), y el
-- cuaderno de una campaña cerrada se genera a partir de esta copia.
--
-- Una fila por cierre: si se reabre y se vuelve a cerrar, queda la historia
-- de los dos. `content_version` es la versión del formato del JSON, para
-- poder leer copias antiguas cuando cambie.
--
-- Inmutable: nadie la modifica ni la borra, tampoco un camino de código
-- olvidadizo. El trigger de abajo lo garantiza.
-- ---------------------------------------------------------------------------
CREATE TABLE campaign_snapshots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  campaign_id     UUID NOT NULL REFERENCES campaigns(id),
  reason          TEXT NOT NULL,
  content         JSONB NOT NULL,
  content_version INTEGER NOT NULL DEFAULT 1,
  created_by      UUID NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT campaign_snapshots_motivo CHECK (reason IN ('close')),
  CONSTRAINT campaign_snapshots_contenido CHECK (jsonb_typeof(content) = 'object')
);

CREATE INDEX campaign_snapshots_organization_id_idx ON campaign_snapshots (organization_id);
CREATE INDEX campaign_snapshots_campaign_id_idx ON campaign_snapshots (campaign_id, created_at DESC);

CREATE OR REPLACE FUNCTION reject_campaign_snapshot_change()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'campaign_snapshots are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campaign_snapshot_immutable
  BEFORE UPDATE OR DELETE ON campaign_snapshots
  FOR EACH ROW EXECUTE FUNCTION reject_campaign_snapshot_change();

-- ---------------------------------------------------------------------------
-- RLS: misma política que el resto de tablas de organización.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['documents', 'document_links', 'campaign_snapshots']
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
