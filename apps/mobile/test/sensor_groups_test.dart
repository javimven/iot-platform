import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/readings/application/reading_history_controller.dart';
import 'package:iot_platform_app/features/stations/application/sensor_groups.dart';
import 'package:iot_platform_app/features/stations/application/stations_controller.dart';

/// Tarjeta de Estación agrupada por sensor: una gráfica por sensor con sus
/// magnitudes, elegibles por separado.
LatestReading _reading(String channelId, String code, {String? sensorId, String? externalId, String? label}) =>
    LatestReading(
      channelId: channelId,
      channelTypeCode: code,
      value: 1,
      tsOrigin: DateTime.utc(2026, 9, 16, 12),
      tsReceived: DateTime.utc(2026, 9, 16, 12),
      sensorId: sensorId,
      sensorExternalIdentifier: externalId,
      sensorLabel: label,
    );

// Como llegan de la API (sin orden garantizado): ambiente, tensiómetro y una sonda de suelo.
final _stationReadings = [
  _reading('ch-temp-air', 'temperature_air', sensorId: 's4', externalId: 'A4', label: 'Ambiente'),
  _reading('ch-temp-soil', 'temperature_soil', sensorId: 's2', externalId: 'A2', label: 'Sonda de suelo redonda'),
  _reading('ch-tension', 'tension_soil', sensorId: 's1', externalId: 'A1', label: 'Tensiómetro'),
  _reading('ch-hum-air', 'humidity_air', sensorId: 's4', externalId: 'A4', label: 'Ambiente'),
  _reading('ch-ec', 'conductivity', sensorId: 's2', externalId: 'A2', label: 'Sonda de suelo redonda'),
  _reading('ch-hum-soil', 'humidity_soil', sensorId: 's2', externalId: 'A2', label: 'Sonda de suelo redonda'),
];

void main() {
  group('groupReadingsBySensor', () {
    test('un grupo por sensor, ordenados por identificador externo', () {
      final groups = groupReadingsBySensor(_stationReadings);
      expect(groups.map((g) => g.externalIdentifier), ['A1', 'A2', 'A4']);
      expect(groups.map((g) => g.label), ['Tensiómetro', 'Sonda de suelo redonda', 'Ambiente']);
    });

    test('los datos del propio equipo (ADR-0008) van al final y se llaman «Estación»', () {
      final groups = groupReadingsBySensor([
        _reading('ch-bat', 'battery_voltage', sensorId: 'st', externalId: '_device'),
        _reading('ch-hum', 'humidity_soil', sensorId: 's1', externalId: 's1', label: 'Sonda'),
      ]);
      // '_' va antes que 's' al ordenar texto: el orden no puede depender de eso.
      expect(groups.map((g) => g.externalIdentifier), ['s1', '_device']);
      expect(groups.last.label, 'Estación');
    });

    test('dentro de cada sensor, sus magnitudes ordenadas por nombre (orden y color estables)', () {
      final soil = groupReadingsBySensor(_stationReadings)[1];
      // Conductividad, Humedad de suelo, Temperatura de suelo.
      expect(soil.readings.map((r) => r.channelId), ['ch-ec', 'ch-hum-soil', 'ch-temp-soil']);
    });

    test('sin datos de sensor en la respuesta, todo va a un único grupo', () {
      final groups = groupReadingsBySensor([_reading('a', 'battery'), _reading('b', 'signal_strength')]);
      expect(groups, hasLength(1));
      expect(groups.single.key, '');
      expect(groups.single.readings, hasLength(2));
    });
  });

  test('LatestReading.fromJson lee el sensor de cada lectura', () {
    final reading = LatestReading.fromJson({
      'channelId': 'ch-1',
      'channelTypeCode': 'humidity_soil',
      'value': 12.5,
      'tsOrigin': '2026-09-16T12:48:08.000Z',
      'tsReceived': '2026-09-16T12:48:09.000Z',
      'sensorId': 's3',
      'sensorExternalIdentifier': 'A3',
      'sensorLabel': 'Sonda de suelo plana',
    });
    expect(reading.sensorId, 's3');
    expect(reading.sensorExternalIdentifier, 'A3');
    expect(reading.sensorLabel, 'Sonda de suelo plana');
  });

  group('gráficas por sensor', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('la tarjeta abre sin ninguna gráfica desplegada', () {
      final c = container();
      expect(c.read(sensorActiveChannelsProvider(('gw-1', 's2'))), isEmpty);
      expect(c.read(sensorActiveChannelsProvider(('gw-1', 's4'))), isEmpty);
    });

    test('elegir magnitudes en un sensor no cambia las de otro', () {
      final c = container();
      c.read(sensorActiveChannelsProvider(('gw-1', 's2')).notifier).state = {'ch-temp-soil', 'ch-hum-soil'};
      expect(c.read(sensorActiveChannelsProvider(('gw-1', 's2'))), {'ch-temp-soil', 'ch-hum-soil'});
      expect(c.read(sensorActiveChannelsProvider(('gw-1', 's4'))), isEmpty);
    });

    test('cada gráfica tiene su propio rango: cambiar uno no mueve los demás', () {
      final c = container();
      expect(c.read(sensorChartRangeProvider(('gw-1', 's2'))), HistoryRange.day);
      c.read(sensorChartRangeProvider(('gw-1', 's2')).notifier).state = HistoryRange.week;
      expect(c.read(sensorChartRangeProvider(('gw-1', 's2'))), HistoryRange.week);
      expect(c.read(sensorChartRangeProvider(('gw-1', 's4'))), HistoryRange.day);
    });
  });
}
