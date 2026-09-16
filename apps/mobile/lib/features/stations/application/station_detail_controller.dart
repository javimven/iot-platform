import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import 'sensor_groups.dart';
import 'stations_controller.dart';

/// Orden de "magnitud principal" de un sensor: la que sale en el resumen de
/// estaciones y la que se dibuja al abrir la pantalla de la estación
/// (BACKLOG.md #49, mejoras B y C). Primero lo que se mira para regar, luego
/// el ambiente y lo demás; un tipo que no esté aquí va después, por nombre.
const primaryChannelOrder = [
  // (Los de estado de la estación van al final: nunca son la principal de un
  // sensor de campo.)
  'tension_soil',
  'humidity_soil',
  'temperature_air',
  'precipitation',
  'temperature_soil',
  'humidity_air',
  'conductivity',
  'tank_level',
  'battery',
  'battery_voltage',
  'signal_strength',
];

/// Canales que describen a la propia estación, no al campo.
const stationHealthChannelTypes = {'battery', 'battery_voltage', 'signal_strength'};

/// Un "sensor" formado solo por canales de estado de la estación (el que manda
/// el puente con batería y cobertura): no sale en el resumen, no cuenta para
/// saber si llegan datos de sensores y en la estación va en su pestaña, al final.
bool isStationHealthGroup(SensorReadings group) =>
    group.readings.isNotEmpty && group.readings.every((r) => stationHealthChannelTypes.contains(r.channelTypeCode));

/// Nombre visible de un grupo: "Estación" para el de estado.
String sensorDisplayLabel(SensorReadings group) => isStationHealthGroup(group) ? 'Estación' : group.label;

/// A partir de cuánto se da por atrasado un dato respecto a lo último que se
/// sabe de la estación: la WSC2-N envía cada 5 minutos, así que 20 son cuatro
/// envíos perdidos.
const staleAfter = Duration(minutes: 20);

/// Lo último que se sabe de la estación: su último dato o su último envío.
DateTime? stationAliveAt(Gateway gateway, List<LatestReading> readings) {
  DateTime? latest = gateway.lastSeenAt;
  for (final r in readings) {
    if (latest == null || r.tsOrigin.isAfter(latest)) latest = r.tsOrigin;
  }
  return latest;
}

/// Si una lectura se ha quedado atrás respecto a lo último que se sabe de la
/// estación (un sensor que ha dejado de contestar).
bool isReadingStale(LatestReading reading, DateTime? aliveAt) =>
    aliveAt != null && aliveAt.difference(reading.tsOrigin) > staleAfter;

enum StationDataState { ok, offline, noSensorData }

/// Estado de los datos de una estación, para avisar en el resumen y en su
/// pantalla (BACKLOG.md #49, mejora F): sin conexión, o enviando pero sin datos
/// de ningún sensor (lo que pasa tras un reinicio o quedarse sin batería, que
/// borra la declaración de los sensores). [since] es desde cuándo.
({StationDataState state, DateTime? since}) stationDataState(Gateway gateway, List<LatestReading> readings) {
  if (gateway.status == 'offline') return (state: StationDataState.offline, since: gateway.lastSeenAt);
  final sensorReadings = [
    for (final group in groupReadingsBySensor(readings))
      if (!isStationHealthGroup(group)) ...group.readings,
  ];
  final aliveAt = stationAliveAt(gateway, readings);
  if (sensorReadings.isNotEmpty && sensorReadings.every((r) => isReadingStale(r, aliveAt))) {
    final newest = sensorReadings.map((r) => r.tsOrigin).reduce((a, b) => a.isAfter(b) ? a : b);
    return (state: StationDataState.noSensorData, since: newest);
  }
  return (state: StationDataState.ok, since: null);
}

/// Pestaña seleccionada en la pantalla de una estación, para no perderla al
/// girar el móvil (la vista a pantalla completa es otro árbol de widgets).
final detailSelectedSensorProvider = StateProvider.family<int, String>((ref, gatewayId) => 0);

int _priority(String channelTypeCode) {
  final index = primaryChannelOrder.indexOf(channelTypeCode);
  return index == -1 ? primaryChannelOrder.length : index;
}

/// Magnitudes de un sensor de la principal a la menos relevante (a igual
/// prioridad, por nombre, que es el orden en que ya llegan). En la pantalla de
/// la estación fija el orden de los interruptores y el estilo de cada serie:
/// la principal lleva el trazo continuo y el primer color.
List<LatestReading> readingsByPriority(SensorReadings group) {
  final indexed = [for (var i = 0; i < group.readings.length; i++) (i, group.readings[i])];
  indexed.sort((a, b) {
    final byPriority = _priority(a.$2.channelTypeCode).compareTo(_priority(b.$2.channelTypeCode));
    return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// La magnitud principal de un sensor.
LatestReading primaryReadingOf(SensorReadings group) => readingsByPriority(group).first;

/// Para el resumen de una estación: la magnitud principal de cada sensor, en
/// el orden de los sensores (A1–A4 en la WSC2-N).
List<({SensorReadings sensor, LatestReading reading})> primaryReadingsPerSensor(List<LatestReading> readings) => [
      for (final group in groupReadingsBySensor(readings))
        if (!isStationHealthGroup(group)) (sensor: group, reading: primaryReadingOf(group)),
    ];

/// El punto de una serie más cercano a un instante (el que marca el dedo en
/// la gráfica). Null si la serie está vacía.
HistoryPoint? nearestPoint(List<HistoryPoint> points, double millisSinceEpoch) {
  HistoryPoint? best;
  var bestDistance = double.infinity;
  for (final p in points) {
    final distance = (p.tsOrigin.millisecondsSinceEpoch - millisSinceEpoch).abs().toDouble();
    if (distance < bestDistance) {
      best = p;
      bestDistance = distance;
    }
  }
  return best;
}

/// Una estación por id, a partir del listado ya cargado (o cargándose).
final stationByIdProvider = Provider.autoDispose.family<AsyncValue<Gateway?>, String>((ref, gatewayId) {
  return ref.watch(allGatewaysProvider).whenData((gateways) {
    for (final gateway in gateways) {
      if (gateway.id == gatewayId) return gateway;
    }
    return null;
  });
});

/// Magnitudes activadas en la pantalla de una estación, por (estación,
/// sensor). Null mientras no se haya tocado ninguna: entonces se dibuja la
/// principal (ver [effectiveDetailChannels]). Aparte de las de la tarjeta de
/// escritorio, que abren cerradas.
final detailActiveChannelsProvider =
    StateProvider.family<Set<String>?, (String gatewayId, String sensorKey)>((ref, key) => null);

Set<String> effectiveDetailChannels(SensorReadings group, Set<String>? manual) =>
    manual ?? {primaryReadingOf(group).channelId};

/// Activa o quita una magnitud en la pantalla de la estación, sin dejarla nunca
/// sin ninguna: esa pantalla existe para ver la gráfica, y en un sensor de una
/// sola magnitud (el tensiómetro) un toque la dejaba en blanco. Visto en un
/// iPhone el 2026-09-16.
Set<String> toggleDetailChannel(Set<String> active, String channelId) {
  if (!active.contains(channelId)) return {...active, channelId};
  if (active.length == 1) return active;
  return {...active}..remove(channelId);
}

/// Instante que marca el dedo en las gráficas de un sensor (milisegundos),
/// compartido por todas sus gráficas apiladas: tocar una marca la misma hora
/// en las demás.
final chartCrosshairProvider =
    StateProvider.autoDispose.family<double?, (String gatewayId, String sensorKey)>((ref, key) => null);

/// Tendencia de 24 h para el resumen: media por hora, 24 puntos, que es lo que
/// cabe en una miniatura y pesa poco.
final stationSparklineProvider =
    FutureProvider.autoDispose.family<List<HistoryPoint>, (String? organizationId, String channelId)>((ref, key) {
  final (organizationId, channelId) = key;
  final to = DateTime.now().toUtc();
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: to.subtract(const Duration(hours: 24)),
        to: to,
        granularity: 'hourly',
        organizationId: organizationId,
      );
});

/// Etiquetas cortas del selector de rango, para que quepan en un móvil.
extension HistoryRangeShortLabel on HistoryRange {
  String get shortLabel => switch (this) {
        HistoryRange.day => '24 h',
        HistoryRange.twoDays => '2 d',
        HistoryRange.week => '7 d',
        HistoryRange.month => '30 d',
        HistoryRange.twoMonths => '60 d',
      };
}

/// Vuelve a pedir todo lo de Estaciones: listado, nombres, últimas lecturas,
/// tendencias e históricos. Lo usan "tirar para actualizar", el botón de
/// actualizar y el refresco automático (BACKLOG.md #49, mejora F). Mientras
/// recarga se sigue viendo lo anterior, sin parpadeos.
void refreshStationData(WidgetRef ref) {
  ref.invalidate(allGatewaysProvider);
  ref.invalidate(stationGroupNamesProvider);
  ref.invalidate(gatewayLatestReadingsProvider);
  ref.invalidate(stationSparklineProvider);
  ref.invalidate(stationChannelHistoryProvider);
  ref.invalidate(stationAccumulatedHistoryProvider);
}
