-- Particiones mensuales de `telemetry` (DATA_MODEL.md §5, BACKLOG.md #45).
--
-- La tabla es PARTITION BY RANGE (ts_origin) y la migración 0003 solo creó la
-- del mes de despliegue: cuando llega un dato de un mes sin partición,
-- PostgreSQL rechaza la inserción con
-- `no partition of relation "telemetry" found for row`. Pasó de verdad el
-- 2026-09-16 con la primera estación real: 323 lecturas se quedaron en la cola
-- como trabajos fallidos hasta que se creó la partición a mano.
--
-- Crear particiones no es una migración de esquema, es mantenimiento
-- periódico, así que esto solo deja la herramienta: una función que crea las
-- que falten. Quien la llama cada pocas horas es el worker
-- (`TelemetryPartitionsService`).
--
-- SECURITY DEFINER a propósito: el rol de la aplicación (`iot_platform_app`)
-- solo tiene SELECT/INSERT/UPDATE/DELETE (DATA_MODEL.md §8) y no puede crear
-- tablas; la función se ejecuta con los permisos de su dueño, que es el dueño
-- de `telemetry`. `search_path` fijado para que nadie pueda colar otra tabla
-- con el mismo nombre desde un esquema propio.
--
-- Las particiones se crean sin RLS propia, igual que las que ya existen: la
-- política `tenant_isolation` vive en la tabla padre y se aplica a todo lo que
-- pase por ella, que es como consulta siempre la aplicación.

CREATE OR REPLACE FUNCTION crear_particiones_telemetry(meses integer DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  creadas integer := 0;
  i integer;
  inicio date;
  fin date;
  nombre text;
BEGIN
  IF meses IS NULL OR meses < 0 OR meses > 24 THEN
    RAISE EXCEPTION 'meses fuera de rango (0-24): %', meses;
  END IF;

  FOR i IN 0..meses LOOP
    inicio := (date_trunc('month', now() AT TIME ZONE 'UTC') + make_interval(months => i))::date;
    fin := (inicio + interval '1 month')::date;
    nombre := 'telemetry_' || to_char(inicio, 'YYYY_MM');

    IF to_regclass(nombre) IS NULL THEN
      EXECUTE format(
        'CREATE TABLE %I PARTITION OF telemetry FOR VALUES FROM (%L) TO (%L)',
        nombre, inicio, fin
      );
      creadas := creadas + 1;
      RAISE NOTICE 'creada la partición %', nombre;
    END IF;
  END LOOP;

  RETURN creadas;
END;
$$;

COMMENT ON FUNCTION crear_particiones_telemetry(integer) IS
  'Crea las particiones mensuales de telemetry que falten, del mes actual hasta N meses después. Idempotente. La llama el worker (BACKLOG.md #45).';

REVOKE ALL ON FUNCTION crear_particiones_telemetry(integer) FROM PUBLIC;

-- El rol de la aplicación no existe en todos los entornos (en local lo crea
-- infra/docker/postgres-init/01-app-role.sql); sin él, el GRANT rompería la
-- migración.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iot_platform_app') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION crear_particiones_telemetry(integer) TO iot_platform_app';
  END IF;
END $$;

-- Las que faltan ahora mismo, para no depender de que el worker arranque.
SELECT crear_particiones_telemetry(3);
