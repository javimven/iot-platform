import '../../installations/data/installation_models.dart';
import 'sensor_groups.dart';
import 'station_detail_controller.dart' show staleAfter;

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
/// Una que se ha quedado atrás respecto a la más reciente del equipo (más de
/// [staleAfter]) tampoco cuenta: la estación ha dejado de mandarla y su última
/// cifra ya no dice cómo está. Pasó con la batería de la WSC2-N, que el puente
/// dejó de mandar al ver que no era la tensión de la batería (informaba 3,45 V
/// con la batería a 4,12 V, medida con multímetro).
///
/// La batería no tiene niveles: no hay una fuente con las tensiones de carga
/// completa y de batería baja, y a ojo no se ponen.
typedef StationHealth = ({LatestReading? battery, LatestReading? signal});

StationHealth stationHealthOf(List<LatestReading> readings) {
  final own = [
    for (final r in readings)
      if (r.sensorExternalIdentifier == deviceStatusSensorId) r,
  ];
  if (own.isEmpty) return (battery: null, signal: null);
  final newest = own.map((r) => r.tsOrigin).reduce((a, b) => a.isAfter(b) ? a : b);

  LatestReading? find(String code) {
    for (final r in own) {
      if (r.channelTypeCode == code && newest.difference(r.tsOrigin) <= staleAfter) return r;
    }
    return null;
  }

  return (battery: find('battery_voltage') ?? find('battery'), signal: find('signal_strength'));
}
