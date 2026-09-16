import '../../installations/data/installation_models.dart';
import '../../readings/application/channel_type_labels.dart';

/// Canales de una Estación que pertenecen a un mismo sensor: en la tarjeta,
/// cada sensor lleva su propia gráfica con sus magnitudes (temperatura,
/// humedad, conductividad...), elegibles por separado.
class SensorReadings {
  /// `sensorId`, o cadena vacía si la API no lo manda (rutas que no son de
  /// una Estación): entonces todo cae en un único grupo.
  final String key;
  final String label;
  final String? externalIdentifier;
  final List<LatestReading> readings;

  const SensorReadings({
    required this.key,
    required this.label,
    required this.externalIdentifier,
    required this.readings,
  });
}

/// Agrupa por sensor, ordenado por identificador externo (en la WSC2-N, la
/// ranura A1–A4). Dentro de cada sensor, las magnitudes van por nombre, de
/// modo que el orden (y el color de cada una en la gráfica) no cambia entre
/// recargas aunque la API las devuelva en otro orden.
List<SensorReadings> groupReadingsBySensor(List<LatestReading> readings) {
  final byKey = <String, List<LatestReading>>{};
  for (final reading in readings) {
    (byKey[reading.sensorId ?? ''] ??= []).add(reading);
  }

  final groups = [
    for (final entry in byKey.entries)
      SensorReadings(
        key: entry.key,
        label: entry.value.first.sensorLabel ?? entry.value.first.sensorExternalIdentifier ?? 'Sensor',
        externalIdentifier: entry.value.first.sensorExternalIdentifier,
        readings: [...entry.value]..sort(
            (a, b) =>
                ChannelTypeLabels.labelFor(a.channelTypeCode).compareTo(ChannelTypeLabels.labelFor(b.channelTypeCode)),
          ),
      ),
  ];
  groups.sort((a, b) => (a.externalIdentifier ?? a.label).compareTo(b.externalIdentifier ?? b.label));
  return groups;
}
