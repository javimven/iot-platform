-- Piezas que Prisma no expresa de forma nativa en schema.prisma (DATA_MODEL.md
-- §7, SECURITY.md §1, PERMISSIONS.md §14). Se aplica DESPUÉS de la migración
-- inicial generada por `prisma migrate dev` (0001, generada automáticamente
-- contra una base de datos real, no incluida a mano en este repositorio).
--
-- `NULLIF(current_setting(...), '')::uuid`, no `current_setting(...)::uuid`
-- a secas — descubierto en vivo (2026-07-28): `set_config(name, NULL, true)`
-- no guarda SQL NULL, lo convierte en cadena vacía (los parámetros GUC de
-- Postgres no distinguen "NULL" de "''"). Sin `NULLIF`, cualquier consulta
-- sin `organizationId`/`userId` todavía conocido (login antes de elegir
-- organización, refresh de sesión, accept-invitation) rompía con
-- `invalid input syntax for type uuid: ""` en vez de simplemente no
-- filtrar por esa condición — invisible mientras la conexión de la
-- aplicación pudiera saltarse RLS (ver infra/docker/postgres-init).

-- ---------------------------------------------------------------------------
-- Índice único parcial: como mucho una credencial ACTIVA por gateway
-- (DATA_MODEL.md, tabla gateway_credentials) — se conserva el historial de
-- credenciales revocadas.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX gateway_credentials_active_uniq
  ON gateway_credentials (gateway_id)
  WHERE status = 'active';

-- ---------------------------------------------------------------------------
-- Regla de integridad Zona<->Gateway (DATA_MODEL.md §4): la zona de un
-- dispositivo debe pertenecer a la misma instalación que su gateway.
-- PostgreSQL no permite un CHECK que consulte otra tabla directamente.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_device_zone_matches_gateway_installation()
RETURNS TRIGGER AS $$
DECLARE
  gateway_installation_id UUID;
  zone_installation_id UUID;
BEGIN
  SELECT installation_id INTO gateway_installation_id FROM gateways WHERE id = NEW.gateway_id;
  SELECT installation_id INTO zone_installation_id FROM zones WHERE id = NEW.zone_id;

  IF gateway_installation_id IS DISTINCT FROM zone_installation_id THEN
    RAISE EXCEPTION 'device.zone_id (installation %) must belong to the same installation as device.gateway_id (installation %)',
      zone_installation_id, gateway_installation_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER device_zone_matches_gateway_installation
  BEFORE INSERT OR UPDATE OF gateway_id, zone_id ON devices
  FOR EACH ROW EXECUTE FUNCTION check_device_zone_matches_gateway_installation();

-- ---------------------------------------------------------------------------
-- Row-Level Security (DATA_MODEL.md §7). Política estándar: aislamiento por
-- organization_id, fijado vía set_config(..., true) parametrizado desde la
-- aplicación (SECURITY.md §1) — nunca SET/SET LOCAL con el valor interpolado.
-- ---------------------------------------------------------------------------
ALTER TABLE org_channel_thresholds ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON org_channel_thresholds USING (
  organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
);

-- `audit_log` necesita, además del aislamiento estándar, que el Admin de
-- plataforma pueda leer su propia auditoría (`platform.audit.read`,
-- PERMISSIONS.md) — las acciones `platform.organizations.*` sí llevan un
-- `organization_id` real (el de la organización afectada, no null), así que
-- la condición "organization_id IS NULL" sola no le habría bastado para
-- verlas (descubierto al implementar el controlador de auditoría, Etapa 13).
-- Sigue sin poder leer auditoría de negocio de una organización que no es la
-- suya salvo que sea, específicamente, una acción `platform.*`.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_or_platform_admin ON audit_log USING (
  organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
  OR organization_id IS NULL
  OR (
    current_setting('app.is_platform_admin', true)::boolean IS TRUE
    AND action LIKE 'platform.%'
  )
);

-- `members` y `sessions`: caso especial descubierto al implementar el login
-- (Etapa 13, no anticipado en la Etapa 5). Antes de que exista una
-- organización activa (login inicial, selección de organización, refresh),
-- la aplicación necesita poder leer las FILAS PROPIAS de un usuario ("¿a qué
-- organizaciones pertenezco?") sin que RLS las bloquee por falta de contexto
-- de organización. Se añade una segunda condición: un usuario siempre puede
-- leer (no escribir más allá de lo que ya permite PERMISSIONS.md) sus propias
-- filas por user_id, independientemente del contexto de organización activo.
-- No es una fuga de aislamiento entre organizaciones: cada usuario solo ve
-- SUS propias membresías/sesiones, nunca las de otro usuario de otra
-- organización.
-- `app.allow_identity_bootstrap`: excepción compartida por `members` y
-- `sessions` (generalizada en Etapa 13 a partir de `app.allow_session_lookup`,
-- que nació pensada solo para `sessions` — al implementar accept-invitation
-- se vio que `members` necesita exactamente el mismo patrón: "localizar una
-- fila por un token opaco antes de conocer user_id/organization_id, verificar
-- el secreto/firma en la aplicación después"). Deliberadamente distinta y más
-- estrecha que la excepción del Admin de plataforma (ADR-0005, que solo cubre
-- Directorio IoT) — esta es sobre identidad (sesiones, invitaciones), no
-- sobre gestión de infraestructura.
-- La condición `is_platform_admin` existe únicamente para que
-- PlatformOrganizationsService.create() pueda escribir el primer Member
-- (Admin de organización) de una organización recién creada
-- (FUNCTIONAL_REQUIREMENTS.md §2: "el admin de plataforma también invita al
-- primer Admin de organización, mismo flujo que el resto de miembros").
-- No amplía lo que el Admin de plataforma puede hacer vía la API: `members.*`
-- sigue marcado No¹ en PERMISSIONS.md — PermissionsGuard nunca deja que
-- llegue a ningún endpoint de `/members` salvo este único flujo de
-- bootstrap, que no pasa por esos endpoints. Ver PERMISSIONS.md nota ³.
ALTER TABLE members ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_or_own_user ON members USING (
  organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
  OR user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid
  OR current_setting('app.allow_identity_bootstrap', true)::boolean IS TRUE
  OR current_setting('app.is_platform_admin', true)::boolean IS TRUE
);

ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_or_own_user ON sessions USING (
  (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid OR organization_id IS NULL)
  OR user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid
  OR current_setting('app.allow_identity_bootstrap', true)::boolean IS TRUE
);

-- Directorio IoT: excepción acotada y auditada para el Admin de plataforma
-- (ADR-0005) — condición OR añadida a la política estándar, no una política
-- separada que la sustituya.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'installations', 'zones', 'gateways', 'devices', 'sensors', 'channels'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation_or_platform_admin ON %I USING (
         organization_id = NULLIF(current_setting(''app.current_org_id'', true), '''')::uuid
         OR current_setting(''app.is_platform_admin'', true)::boolean IS TRUE
       )', t
    );
  END LOOP;
END $$;

-- gateway_credentials y member_installation_scope no tienen organization_id
-- propio (cuelgan de gateways/members) — RLS se aplica a través de un JOIN
-- implícito en cada consulta de la aplicación, no aquí (no hay columna sobre
-- la que escribir una política directa sin desnormalizar, y no se justifica
-- solo por estas dos tablas de bajo volumen).

-- organization_features: lectura por tenant, escritura solo Admin de
-- plataforma (PERMISSIONS.md §14, DATA_MODEL.md sección de la tabla).
ALTER TABLE organization_features ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_read ON organization_features FOR SELECT
  USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid);

CREATE POLICY platform_admin_write ON organization_features FOR ALL
  USING (current_setting('app.is_platform_admin', true)::boolean IS TRUE)
  WITH CHECK (current_setting('app.is_platform_admin', true)::boolean IS TRUE);

-- El rol de aplicación (usado por api/ingestion/worker) nunca debe tener
-- BYPASSRLS ni ser superusuario (DATA_MODEL.md §7, SECURITY.md §2). Se crea
-- y se otorga en el script de aprovisionamiento de la base de datos (Etapa 9,
-- Terraform), no aquí, para no atar el nombre del rol a esta migración.
