-- Telemetría y alertas (DATA_MODEL.md §5). `telemetry` se crea a mano
-- particionada (PARTITION BY RANGE) — Prisma no expresa esto de forma
-- nativa, así que esta migración sustituye al CREATE TABLE plano que Prisma
-- habría generado a partir de `model Telemetry` (mismo criterio que la
-- migración 0002 con RLS). Las columnas coinciden exactamente con el modelo
-- de schema.prisma para que el cliente Prisma y la tabla real no diverjan.

CREATE TABLE telemetry (
  channel_id       UUID NOT NULL REFERENCES channels(id),
  organization_id  UUID NOT NULL REFERENCES organizations(id),
  ts_origin        TIMESTAMPTZ NOT NULL,
  ts_received      TIMESTAMPTZ NOT NULL DEFAULT now(),
  value            DOUBLE PRECISION NOT NULL,
  message_id       TEXT,
  PRIMARY KEY (channel_id, ts_origin)
) PARTITION BY RANGE (ts_origin);

-- Partición del mes de despliegue inicial. La creación de particiones
-- futuras es un job operativo programado (DATA_MODEL.md §5, DEPLOYMENT.md
-- §9), no parte del ciclo normal de migraciones — se documenta aquí solo la
-- partición mínima para que la tabla sea utilizable desde el primer
-- despliegue.
CREATE TABLE telemetry_2026_07 PARTITION OF telemetry
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE latest_readings (
  channel_id      UUID PRIMARY KEY REFERENCES channels(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  value           DOUBLE PRECISION NOT NULL,
  ts_origin       TIMESTAMPTZ NOT NULL,
  ts_received     TIMESTAMPTZ NOT NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE alerts (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    UUID NOT NULL REFERENCES organizations(id),
  alert_type         TEXT NOT NULL CHECK (alert_type IN ('threshold', 'offline')),
  channel_id         UUID REFERENCES channels(id),
  device_id          UUID REFERENCES devices(id),
  gateway_id         UUID REFERENCES gateways(id),
  status             TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'resolved')),
  opened_at          TIMESTAMPTZ NOT NULL,
  acknowledged_at    TIMESTAMPTZ,
  acknowledged_by    UUID,
  resolved_at        TIMESTAMPTZ,
  resolved_by        UUID,
  details            JSONB,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX alerts_org_status_idx ON alerts (organization_id, status);

-- Una única alerta abierta por causa (DATA_MODEL.md §5, FUNCTIONAL_REQUIREMENTS.md §14).
CREATE UNIQUE INDEX alerts_open_threshold_uniq ON alerts (channel_id, alert_type)
  WHERE status <> 'resolved' AND channel_id IS NOT NULL;
CREATE UNIQUE INDEX alerts_open_device_offline_uniq ON alerts (device_id, alert_type)
  WHERE status <> 'resolved' AND device_id IS NOT NULL;
CREATE UNIQUE INDEX alerts_open_gateway_offline_uniq ON alerts (gateway_id, alert_type)
  WHERE status <> 'resolved' AND gateway_id IS NOT NULL AND device_id IS NULL;

CREATE TABLE notification_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID NOT NULL REFERENCES organizations(id),
  alert_id          UUID NOT NULL REFERENCES alerts(id),
  recipient_user_id UUID NOT NULL REFERENCES users(id),
  channel           TEXT NOT NULL DEFAULT 'email' CHECK (channel IN ('email')),
  status            TEXT NOT NULL CHECK (status IN ('sent', 'failed')),
  sent_at           TIMESTAMPTZ NOT NULL,
  error             TEXT,
  UNIQUE (alert_id, recipient_user_id)
);

-- RLS: aislamiento multitenant estándar (DATA_MODEL.md §7) — sin la
-- excepción del Admin de plataforma (ADR-0005 se limita a Directorio IoT,
-- nunca a datos de negocio/telemetría/alertas).
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['telemetry', 'latest_readings', 'alerts', 'notification_log']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING (
         organization_id = NULLIF(current_setting(''app.current_org_id'', true), '''')::uuid
       )', t
    );
  END LOOP;
END $$;
