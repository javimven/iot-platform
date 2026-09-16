import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/core/format/relative_time.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/readings/application/reading_history_controller.dart';
import 'package:iot_platform_app/features/readings/data/reading_history_models.dart';
import 'package:iot_platform_app/features/stations/application/sensor_groups.dart';
import 'package:iot_platform_app/features/stations/application/station_detail_controller.dart';

/// Lógica del resumen y de la pantalla de estación (BACKLOG.md #49, B, C y D).
LatestReading _reading(String channelId, String code, String sensorId, String externalId, String label) => LatestReading(
      channelId: channelId,
      channelTypeCode: code,
      value: 1,
      tsOrigin: DateTime.utc(2026, 9, 16, 12),
      tsReceived: DateTime.utc(2026, 9, 16, 12),
      sensorId: sensorId,
      sensorExternalIdentifier: externalId,
      sensorLabel: label,
    );

final _station = [
  _reading('a1-tension', 'tension_soil', 's1', 'A1', 'Tensiómetro'),
  _reading('a2-ec', 'conductivity', 's2', 'A2', 'Suelo redondo'),
  _reading('a2-temp', 'temperature_soil', 's2', 'A2', 'Suelo redondo'),
  _reading('a2-hum', 'humidity_soil', 's2', 'A2', 'Suelo redondo'),
  _reading('a4-hum', 'humidity_air', 's4', 'A4', 'Ambiente'),
  _reading('a4-temp', 'temperature_air', 's4', 'A4', 'Ambiente'),
];

void main() {
  group('formatAgo', () {
    final now = DateTime(2026, 9, 16, 14, 0);
    test('minutos, horas y días', () {
      expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'hace un momento');
      expect(formatAgo(now.subtract(const Duration(minutes: 3)), now: now), 'hace 3 min');
      expect(formatAgo(now.subtract(const Duration(hours: 5)), now: now), 'hace 5 h');
      expect(formatAgo(now.subtract(const Duration(days: 1, hours: 2)), now: now), 'hace 1 día');
      expect(formatAgo(now.subtract(const Duration(days: 3)), now: now), 'hace 3 días');
    });
  });

  group('magnitud principal', () {
    test('en una sonda de suelo es la humedad, no la conductividad aunque vaya antes por nombre', () {
      final soil = groupReadingsBySensor(_station)[1];
      expect(soil.readings.first.channelId, 'a2-ec'); // orden por nombre, el de los colores
      expect(primaryReadingOf(soil).channelId, 'a2-hum');
    });

    test('en la pantalla de estación la principal va primero y el resto por nombre', () {
      final soil = groupReadingsBySensor(_station)[1];
      expect(readingsByPriority(soil).map((r) => r.channelId), ['a2-hum', 'a2-temp', 'a2-ec']);
    });

    test('el resumen lleva una por sensor, en el orden de los sensores', () {
      final primary = primaryReadingsPerSensor(_station);
      expect(primary.map((p) => p.reading.channelId), ['a1-tension', 'a2-hum', 'a4-temp']);
      expect(primary.map((p) => p.sensor.externalIdentifier), ['A1', 'A2', 'A4']);
    });

    test('la pantalla de estación dibuja la principal mientras no se toque nada', () {
      final soil = groupReadingsBySensor(_station)[1];
      expect(effectiveDetailChannels(soil, null), {'a2-hum'});
      expect(effectiveDetailChannels(soil, {'a2-temp'}), {'a2-temp'});
      expect(effectiveDetailChannels(soil, const {}), isEmpty);
    });
  });

  test('toggleDetailChannel: añade y quita, pero nunca deja la pantalla sin gráfica', () {
    expect(toggleDetailChannel({'hum'}, 'temp'), {'hum', 'temp'});
    expect(toggleDetailChannel({'hum', 'temp'}, 'hum'), {'temp'});
    expect(toggleDetailChannel({'tension'}, 'tension'), {'tension'});
  });

  test('nearestPoint: el punto más cercano al instante tocado', () {
    HistoryPoint p(int hour) => HistoryPoint(tsOrigin: DateTime.utc(2026, 9, 16, hour), value: hour.toDouble(), min: null, max: null);
    final points = [p(8), p(10), p(12)];
    expect(nearestPoint(points, DateTime.utc(2026, 9, 16, 10, 50).millisecondsSinceEpoch.toDouble())?.value, 10);
    expect(nearestPoint(points, DateTime.utc(2026, 9, 16, 11, 10).millisecondsSinceEpoch.toDouble())?.value, 12);
    expect(nearestPoint(const [], 0), isNull);
  });

  test('etiquetas cortas del rango, para que quepan en el móvil', () {
    expect(HistoryRange.values.map((r) => r.shortLabel), ['24 h', '2 d', '7 d', '30 d', '60 d']);
  });
}
