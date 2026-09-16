-- Particiones mensuales de `telemetry` (DATA_MODEL.md §5 y §466).
--
-- Crear la partición del mes siguiente **no es una migración de esquema**: es
-- la tarea operativa programada que la Etapa 9 dejó pendiente. Hasta que
-- exista ese job, se aplica a mano con este archivo.
--
-- Por qué hizo falta (2026-09-16): en staging solo existía `telemetry_2026_07`,
-- la que creó `0003_telemetry_and_alerts`. Con las primeras lecturas reales de
-- la estación WSC2-N (BACKLOG.md #44) el worker fallaba en cada intento con
-- "no partition of relation telemetry found for row", así que `telemetry` y
-- `latest_readings` seguían vacías aunque los canales sí se crearan.
--
-- Uso, desde Git Bash y con la clave de administrador de la VPS:
--
--   ssh -i /c/Users/javim/.ssh/iot_platform_admin root@2.28.10.232 \
--     'set -a; . /opt/iot-platform/.env; set +a; \
--      docker run --rm -i --network host postgres:16-alpine \
--        psql "$DATABASE_URL_MIGRATE" -f -' < infra/docker/particiones-telemetry.sql
--
-- Es aditivo e idempotente (IF NOT EXISTS) y una partición vacía se puede
-- borrar con DROP TABLE. Añade meses nuevos aquí cuando toque.

CREATE TABLE IF NOT EXISTS telemetry_2026_08 PARTITION OF telemetry
  FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS telemetry_2026_09 PARTITION OF telemetry
  FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS telemetry_2026_10 PARTITION OF telemetry
  FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS telemetry_2026_11 PARTITION OF telemetry
  FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS telemetry_2026_12 PARTITION OF telemetry
  FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

-- Comprobación: debe listar julio a diciembre de 2026.
SELECT c.relname, pg_get_expr(c.relpartbound, c.oid) AS rango
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class p ON p.oid = i.inhparent
WHERE p.relname = 'telemetry'
ORDER BY 1;
