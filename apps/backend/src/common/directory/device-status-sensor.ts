/**
 * `sensor_id` reservado para los datos del propio equipo (batería, cobertura),
 * que no vienen de ninguna sonda conectada (ADR-0008). No hay que darlo de alta:
 * `ingestion` lo crea la primera vez que llega con un dispositivo pre-registrado
 * (MQTT_PROTOCOL.md §6, punto 4). No cuenta para el máximo de sensores de un
 * dispositivo (FUNCTIONAL_REQUIREMENTS.md §7), no sale en el Directorio IoT y
 * no se puede registrar a mano.
 */
export const DEVICE_STATUS_SENSOR_ID = '_device';
