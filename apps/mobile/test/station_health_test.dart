import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/stations/application/station_health.dart';

/// Batería y cobertura de la estación como iconos (BACKLOG.md #49 F).
LatestReading _reading(String code, double value, String externalId) => LatestReading(
      channelId: '$externalId-$code',
      channelTypeCode: code,
      value: value,
      tsOrigin: DateTime.utc(2026, 9, 17, 10),
      tsReceived: DateTime.utc(2026, 9, 17, 10),
      sensorId: externalId,
      sensorExternalIdentifier: externalId,
      sensorLabel: null,
    );

void main() {
  test('niveles de cobertura con los cortes de la tabla del CSQ (−113 + 2·CSQ)', () {
    double dbm(int csq) => -113.0 + 2 * csq;
    expect(signalLevelFor(dbm(0)), SignalLevel.weak);
    expect(signalLevelFor(dbm(9)), SignalLevel.weak); // −95, marginal
    expect(signalLevelFor(dbm(10)), SignalLevel.fair); // −93, OK
    expect(signalLevelFor(dbm(14)), SignalLevel.fair); // −85
    expect(signalLevelFor(dbm(15)), SignalLevel.good); // −83, buena
    expect(signalLevelFor(dbm(19)), SignalLevel.good); // −75, la de la WSC2-N en pruebas
    expect(signalLevelFor(dbm(20)), SignalLevel.excellent); // −73, excelente
    expect(signalLevelFor(dbm(31)), SignalLevel.excellent);
  });

  test('batería y cobertura salen solo de los datos del propio equipo', () {
    final health = stationHealthOf([
      _reading('battery', 80, 'A1'), // la batería de una sonda no es la de la estación
      _reading('battery_voltage', 3.451, '_device'),
      _reading('signal_strength', -77, '_device'),
    ]);
    expect(health.battery?.value, 3.451);
    expect(health.signal?.value, -77);

    final none = stationHealthOf([_reading('humidity_soil', 31, 'A3')]);
    expect(none.battery, isNull);
    expect(none.signal, isNull);
  });
}
