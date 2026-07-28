-- Rol de aplicación sin privilegios de superusuario (DATA_MODEL.md §7,
-- SECURITY.md §2: "el rol de aplicación nunca debe tener BYPASSRLS ni ser
-- superusuario"). El usuario `POSTGRES_USER` del contenedor (`iot_platform`)
-- es el superusuario de arranque de la imagen oficial de Postgres — nunca
-- debe usarlo la aplicación para conectarse, solo las migraciones (DDL).
--
-- Descubierto en vivo (2026-07-28, primera vez que este proyecto corrió
-- contra un Postgres real): sin este rol separado, RLS quedaba
-- silenciosamente sin efecto — un superusuario/dueño de las tablas se
-- salta cualquier política de RLS por diseño de PostgreSQL, con o sin
-- `ENABLE ROW LEVEL SECURITY`. Verificado con dos organizaciones reales:
-- antes de este script, cada una veía las instalaciones de la otra; después,
-- el aislamiento funciona (404, no 403, al intentar acceder por ID a un
-- recurso de otra organización — PERMISSIONS.md §9/§13).
--
-- Se ejecuta una única vez, al crear el volumen de datos por primera vez
-- (docker-entrypoint-initdb.d de la imagen oficial de postgres). Las
-- migraciones (`prisma migrate deploy`) siguen corriendo como `iot_platform`
-- (dueño de las tablas, necesario para DDL); solo `api`/`ingestion`/`worker`
-- se conectan como `iot_platform_app`.

CREATE ROLE iot_platform_app LOGIN PASSWORD 'dev_only_app_password'
  NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;

GRANT USAGE ON SCHEMA public TO iot_platform_app;

-- Tablas creadas por migraciones ANTERIORES a este script (no debería haber
-- ninguna en un volumen nuevo, pero es idempotente si algún día se
-- reordenara la inicialización).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO iot_platform_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO iot_platform_app;

-- Tablas creadas por migraciones POSTERIORES a este script (el caso normal:
-- este script corre antes de que exista ninguna tabla de la aplicación).
ALTER DEFAULT PRIVILEGES FOR ROLE iot_platform IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO iot_platform_app;
ALTER DEFAULT PRIVILEGES FOR ROLE iot_platform IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO iot_platform_app;
