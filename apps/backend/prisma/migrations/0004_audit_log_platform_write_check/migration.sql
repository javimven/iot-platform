-- Bug real de RLS encontrado en vivo (2026-07-30): PlatformFeaturesService
-- #setForOrganization escribe en audit_log con action = 'org_features.update'
-- (nunca 'platform.*') y organization_id = la organización afectada (no la
-- del Admin de plataforma, que no tiene ninguna). La política de la
-- migración 0002 (tenant_isolation_or_platform_admin) no tiene un WITH CHECK
-- propio, así que Postgres reutiliza la misma expresión de USING para
-- comprobar también los INSERT — y esa expresión exige, para el caso de
-- Admin de plataforma, que `action LIKE 'platform.%'`. Como 'org_features.update'
-- no lo cumple, ninguna de las tres condiciones es cierta y el INSERT viola
-- RLS ("new row violates row-level security policy for table audit_log"),
-- con 500 en cualquier alta/baja de función de organización.
--
-- La restricción de USING (qué puede LEER un Admin de plataforma: solo
-- acciones 'platform.*' de organizaciones ajenas, nunca su auditoría de
-- negocio completa) sigue siendo la correcta y se mantiene intacta — el
-- error estaba en reutilizar esa misma expresión, más estrecha, para decidir
-- qué puede ESCRIBIR. Cualquier escritura que llega hasta aquí ya pasó por
-- el guard de permisos de NestJS (RequirePermission), que es quien de verdad
-- autoriza la acción de negocio; RLS solo debe impedir que el proceso
-- escriba filas de una organización que no le corresponde, no repetir esa
-- autorización por el nombre del string de `action`.
ALTER POLICY tenant_isolation_or_platform_admin ON audit_log
  USING (
    organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
    OR organization_id IS NULL
    OR (
      current_setting('app.is_platform_admin', true)::boolean IS TRUE
      AND action LIKE 'platform.%'
    )
  )
  WITH CHECK (
    organization_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
    OR organization_id IS NULL
    OR current_setting('app.is_platform_admin', true)::boolean IS TRUE
  );
