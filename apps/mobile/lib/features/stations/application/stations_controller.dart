import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import '../data/stations_api.dart';

final stationsApiProvider = Provider<StationsApi>(
  (ref) => StationsApi(ref.watch(apiClientProvider)),
);

final allGatewaysProvider = FutureProvider.autoDispose<List<Gateway>>(
  (ref) => ref.watch(stationsApiProvider).allGateways(),
);

final gatewayLatestReadingsProvider =
    FutureProvider.autoDispose.family<List<LatestReading>, String>(
  (ref, gatewayId) => ref.watch(stationsApiProvider).latestReadingsForGateway(gatewayId),
);

/// Un único buscador para todo el listado (filtra por nombre en cliente,
/// mismo criterio ya aceptado en `DirectoryApi.gatewaysForInstallation`).
final stationSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Estaciones marcadas en el listado de selección — vacío por defecto
/// ("Estaciones seleccionadas: 0", mockup original). Solo las marcadas
/// muestran su tarjeta con datos.
final selectedGatewayIdsProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

/// Por estación, no global (a diferencia de `historyRangeProvider`): varias
/// tarjetas pueden estar abiertas a la vez, cada una con su propio rango.
final stationChartRangeProvider =
    StateProvider.family<HistoryRange, String>((ref, gatewayId) => HistoryRange.day);

/// Minimizado a mano por el usuario (botón en la cabecera de la tarjeta) —
/// oculta solo la gráfica, las píldoras siguen visibles.
final stationChartMinimizedProvider = StateProvider.family<bool, String>((ref, gatewayId) => false);

/// Canales activados (píldoras pulsadas) por estación, elegidos a mano por
/// el usuario — vacío mientras no haya tocado ninguna píldora todavía.
/// Ver [effectiveActiveChannelsProvider] para el conjunto que de verdad se
/// pinta (con el primer canal ya activado por defecto).
final stationActiveChannelsProvider =
    StateProvider.family<Set<String>, String>((ref, gatewayId) => {});

/// Conjunto de canales a mostrar en la gráfica de una estación: el elegido a
/// mano si el usuario ya tocó alguna píldora, o si no, el primero que
/// reporte la estación — para que la gráfica se vea directamente al abrir
/// la tarjeta, sin un paso extra de "toca una píldora primero".
final effectiveActiveChannelsProvider = Provider.family<Set<String>, String>((ref, gatewayId) {
  final manual = ref.watch(stationActiveChannelsProvider(gatewayId));
  if (manual.isNotEmpty) return manual;
  final readings = ref.watch(gatewayLatestReadingsProvider(gatewayId));
  return readings.maybeWhen(
    data: (items) => items.isEmpty ? const {} : {items.first.channelId},
    orElse: () => const {},
  );
});

/// Histórico de un canal (agregación `average`) para el rango de SU
/// tarjeta — reutiliza `ReadingsApi.history` ya existente
/// (readings/application), solo añade la clave compuesta (canal + rango).
final stationChannelHistoryProvider = FutureProvider.autoDispose
    .family<List<HistoryPoint>, (String channelId, HistoryRange range)>((ref, key) {
  final (channelId, range) = key;
  final to = DateTime.now().toUtc();
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: to.subtract(range.span),
        to: to,
        granularity: range.granularity,
      );
});

/// Histórico de un canal "de acumulados" (lluvia) para [AccumulatedChart] —
/// deliberadamente NO usa `HistoryRangeX.granularity` (pensada para las
/// líneas): 1 día/2 días necesitan el dato en crudo (para agrupar por
/// franjas de 6h en hora local, `AccumulatedChart._buildSlots`) y
/// semana/mes/2 meses necesitan `daily` siempre (acumulado por día, pedido
/// explícito — no `hourly` para semana como sí usan las líneas).
final stationAccumulatedHistoryProvider = FutureProvider.autoDispose
    .family<List<HistoryPoint>, (String channelId, HistoryRange range)>((ref, key) {
  final (channelId, range) = key;
  final isShortRange = range == HistoryRange.day || range == HistoryRange.twoDays;

  if (isShortRange) {
    final now = DateTime.now();
    final days = range == HistoryRange.day ? 1 : 2;
    final todayStart = DateTime(now.year, now.month, now.day);
    final from = todayStart.subtract(Duration(days: days - 1));
    return ref.watch(readingsApiProvider).history(
          channelId: channelId,
          from: from.toUtc(),
          to: now.toUtc(),
          granularity: 'raw',
        );
  }

  final to = DateTime.now().toUtc();
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: to.subtract(range.span),
        to: to,
        granularity: 'daily',
      );
});
