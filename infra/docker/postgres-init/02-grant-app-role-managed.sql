-- Equivalente de 01-app-role.sql para DigitalOcean Managed Postgres
-- (DEPLOYMENT.md §7, infra/terraform/modules/database) — a diferencia del
-- Postgres en contenedor local, aquí NO hace falta `CREATE ROLE`:
-- `digitalocean_database_user.app` (Terraform) ya crea el rol de
-- aplicación `iot_platform_app` con rol `normal` (nunca `primary`, DO no
-- deja que un usuario así creado sea superusuario — ver el comentario en
-- el propio módulo). Lo que SÍ hace falta, y Terraform no puede hacer por
-- sí solo (las tablas todavía no existen cuando se aplica), son los
-- GRANT/ALTER DEFAULT PRIVILEGES — igual que en local, sin ellos RLS queda
-- activo pero el rol no puede leer/escribir nada (DATA_MODEL.md §7).
--
-- Se ejecuta con las credenciales del usuario admin de DO (`doadmin` u
-- otro nombre según el proveedor — `CURRENT_USER` evita tener que
-- hardcodearlo), vía infra/docker/deploy.sh, ANTES de arrancar
-- api/ingestion/worker por primera vez contra una base de datos nueva.
-- Idempotente: seguro de volver a ejecutar en cada despliegue (GRANT y
-- ALTER DEFAULT PRIVILEGES no fallan si ya estaban concedidos).

GRANT USAGE ON SCHEMA public TO iot_platform_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO iot_platform_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO iot_platform_app;

ALTER DEFAULT PRIVILEGES FOR ROLE CURRENT_USER IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO iot_platform_app;
ALTER DEFAULT PRIVILEGES FOR ROLE CURRENT_USER IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO iot_platform_app;
