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
  'tension_soil',
  'humidity_soil',
  'temperature_air',
  'precipitation',
  'temperature_soil',
  'humidity_air',
  'conductivity',
  'tank_level',
  'battery',
  'signal_strength',
];

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
      for (final group in groupReadingsBySensor(readings)) (sensor: group, reading: primaryReadingOf(group)),
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
