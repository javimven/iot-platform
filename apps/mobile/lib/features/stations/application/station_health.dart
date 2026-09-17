import '../../installations/data/installation_models.dart';
import 'sensor_groups.dart';

/// Nivel de cobertura de una estación a partir de su intensidad de señal en dBm.
///
/// Es la tabla habitual del CSQ de los módems (M2MSupport, «AT+CSQ – Signal
/// quality»: 2–9 marginal, 10–14 OK, 15–19 buena, 20–30 excelente), pasada a
/// dBm con −113 + 2·CSQ (3GPP TS 27.007): marginal hasta −95, OK de −93 a −85,
/// buena de −83 a −75 y excelente desde −73. Por debajo de la tabla (CSQ 0 y 1)
/// también cuenta como débil.
enum SignalLevel {
  weak('débil', 1),
  fair('aceptable', 2),
  good('buena', 3),
  excellent('excelente', 4);

  const SignalLevel(this.label, this.bars);

  final String label;

  /// Barras encendidas de cuatro.
  final int bars;
}

SignalLevel signalLevelFor(double dbm) {
  if (dbm >= -73) return SignalLevel.excellent;
  if (dbm >= -83) return SignalLevel.good;
  if (dbm >= -93) return SignalLevel.fair;
  return SignalLevel.weak;
}

/// Batería y cobertura de la propia estación, las lecturas del sensor
/// reservado de datos del equipo (ADR-0008); `null` si no las manda.
///
/// La batería no tiene niveles todavía: el manual de la WSC2-N solo dice que es
/// una Li-ion recargable de 1000 mAh, sin tensiones de carga completa ni de
/// batería baja, y a ojo no se ponen (ficha de la estación en rs485-tool).
typedef StationHealth = ({LatestReading? battery, LatestReading? signal});

StationHealth stationHealthOf(List<LatestReading> readings) {
  LatestReading? find(String code) {
    for (final r in readings) {
      if (r.sensorExternalIdentifier == deviceStatusSensorId && r.channelTypeCode == code) return r;
    }
    return null;
  }

  return (battery: find('battery_voltage') ?? find('battery'), signal: find('signal_strength'));
}
