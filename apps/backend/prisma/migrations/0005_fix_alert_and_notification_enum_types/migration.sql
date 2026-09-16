-- `0003_telemetry_and_alerts` (migración escrita a mano) creó `alerts.alert_type`/
-- `alerts.status` y `notification_log.channel`/`notification_log.status` como
-- TEXT + CHECK, en vez de los tipos enum de Postgres que `schema.prisma` ya
-- declaraba (`AlertType`/`AlertStatus`/`NotificationChannel`/`NotificationStatus`,
-- creados correctamente por `0001_init` pero nunca usados por estas dos
-- tablas). Bug real encontrado en vivo (2026-08-05) verificando el pipeline
-- de telemetría MQTT de punta a punta por primera vez (BACKLOG.md #30,
-- pantalla "Estaciones"): cualquier lectura real hacía que
-- `TelemetryProcessingService.touchLastSeen` (que sí filtra `alertType`/
-- `status` como si fueran los enums declarados) fallara con
-- "operator does not exist: text = "AlertType"" — Postgres generaba
-- correctamente el CAST del parámetro al tipo enum, pero la columna real
-- nunca fue de ese tipo. La transacción entera de `processMessage` revertía,
-- así que **ninguna lectura MQTT real llegaba nunca a `telemetry`/
-- `latest_readings`**, en cualquier entorno (no solo desarrollo).
--
-- Los índices únicos parciales que referencian `status <> 'resolved'`
-- (DATA_MODEL.md §5) se recrean igual, ahora contra la columna ya tipada.

-- alerts.alert_type / alerts.status
DROP INDEX alerts_open_device_offline_uniq;
DROP INDEX alerts_open_gateway_offline_uniq;
DROP INDEX alerts_open_threshold_uniq;
ALTER TABLE alerts DROP CONSTRAINT alerts_alert_type_check;
ALTER TABLE alerts DROP CONSTRAINT alerts_status_check;
ALTER TABLE alerts ALTER COLUMN status DROP DEFAULT;

ALTER TABLE alerts ALTER COLUMN alert_type TYPE "AlertType" USING alert_type::"AlertType";
ALTER TABLE alerts ALTER COLUMN status TYPE "AlertStatus" USING status::"AlertStatus";
ALTER TABLE alerts ALTER COLUMN status SET DEFAULT 'open'::"AlertStatus";

CREATE UNIQUE INDEX alerts_open_threshold_uniq ON alerts (channel_id, alert_type)
  WHERE status <> 'resolved' AND channel_id IS NOT NULL;
CREATE UNIQUE INDEX alerts_open_device_offline_uniq ON alerts (device_id, alert_type)
  WHERE status <> 'resolved' AND device_id IS NOT NULL;
CREATE UNIQUE INDEX alerts_open_gateway_offline_uniq ON alerts (gateway_id, alert_type)
  WHERE status <> 'resolved' AND gateway_id IS NOT NULL AND device_id IS NULL;

-- notification_log.channel / notification_log.status
ALTER TABLE notification_log DROP CONSTRAINT notification_log_channel_check;
ALTER TABLE notification_log DROP CONSTRAINT notification_log_status_check;
ALTER TABLE notification_log ALTER COLUMN channel DROP DEFAULT;

ALTER TABLE notification_log ALTER COLUMN channel TYPE "NotificationChannel" USING channel::"NotificationChannel";
ALTER TABLE notification_log ALTER COLUMN channel SET DEFAULT 'email'::"NotificationChannel";
ALTER TABLE notification_log ALTER COLUMN status TYPE "NotificationStatus" USING status::"NotificationStatus";
