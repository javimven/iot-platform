import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/application/installations_controller.dart';
import '../../installations/data/installation_models.dart';
import '../../organization/data/organization_models.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import '../data/stations_api.dart';

final stationsApiProvider = Provider<StationsApi>(
  (ref) => StationsApi(ref.watch(apiClientProvider)),
);

/// El Admin de plataforma ve las estaciones de todas las organizaciones, en
/// solo lectura (ADR-0007), tenga o no además una organización activa.
final stationsAcrossOrganizationsProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider.select((state) => state.isPlatformAdmin)),
);

/// Organizaciones de la vista de plataforma, pedidas una sola vez para las
/// estaciones y para los nombres de finca (antes eran dos peticiones iguales).
final stationOrganizationsProvider = FutureProvider.autoDispose<List<OrganizationProfile>>(
  (ref) => ref.watch(stationsApiProvider).organizations(),
);

final allGatewaysProvider = FutureProvider.autoDispose<List<Gateway>>((ref) async {
  final api = ref.watch(stationsApiProvider);
  if (!ref.watch(stationsAcrossOrganizationsProvider)) {
    return api.allGateways();
  }
  final organizations = await ref.watch(stationOrganizationsProvider.future);
  final perOrganization = await Future.wait(organizations.map((o) => api.gatewaysOfOrganization(o.id)));
  return [for (final gateways in perOrganization) ...gateways];
});

/// Cabecera de un grupo del listado: la finca y, en la vista de plataforma,
/// donde se mezclan fincas de varios clientes, también su organización.
typedef StationGroupName = ({String farm, String? organization});

/// Cabecera de cada grupo del listado, por `installationId`.
final stationGroupNamesProvider = FutureProvider.autoDispose<Map<String, StationGroupName>>((ref) async {
  final api = ref.watch(stationsApiProvider);
  if (!ref.watch(stationsAcrossOrganizationsProvider)) {
    final installations = await ref.watch(installationsApiProvider).list();
    return {for (final i in installations) i.id: (farm: i.name, organization: null)};
  }
  final organizations = await ref.watch(stationOrganizationsProvider.future);
  final perOrganization = await Future.wait(organizations.map((o) => api.installationsOfOrganization(o.id)));
  return {
    for (var n = 0; n < organizations.length; n++)
      for (final i in perOrganization[n]) i.id: (farm: i.name, organization: organizations[n].name),
  };
});

/// Organización por la que pedir los datos de una estación: la suya en la
/// vista de plataforma (ruta `/platform/organizations/{id}/...`), o null para
/// un miembro (ruta de miembro, organización implícita del JWT).
final stationOrganizationIdProvider = Provider.autoDispose.family<String?, String>((ref, gatewayId) {
  if (!ref.watch(stationsAcrossOrganizationsProvider)) return null;
  final gateways = ref.watch(allGatewaysProvider).valueOrNull ?? const <Gateway>[];
  for (final gateway in gateways) {
    if (gateway.id == gatewayId) return gateway.organizationId;
  }
  return null;
});

final gatewayLatestReadingsProvider = FutureProvider.autoDispose.family<List<LatestReading>, String>(
  (ref, gatewayId) => ref.watch(stationsApiProvider).latestReadingsForGateway(
        gatewayId,
        organizationId: ref.watch(stationOrganizationIdProvider(gatewayId)),
      ),
);

/// Un único buscador para todo el listado (filtra por nombre en cliente,
/// mismo criterio ya aceptado en `DirectoryApi.gatewaysForInstallation`).
final stationSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Estaciones marcadas en el listado de selección — vacío por defecto
/// ("Estaciones seleccionadas: 0", mockup original). Solo las marcadas
/// muestran su tarjeta con datos.
final selectedGatewayIdsProvider = StateProvider.autoDispose<Set<String>>((ref) => {});

/// Rango de la gráfica de un sensor, por (estación, sensor): cada gráfica
/// abierta lleva su propio selector encima, así que cambiar uno no mueve las
/// demás.
final sensorChartRangeProvider =
    StateProvider.family<HistoryRange, (String gatewayId, String sensorKey)>((ref, key) => HistoryRange.day);

/// Minimizado a mano por el usuario (botón en la cabecera de la tarjeta) —
/// oculta las gráficas abiertas, las píldoras siguen visibles.
final stationChartMinimizedProvider = StateProvider.family<bool, String>((ref, gatewayId) => false);

/// Magnitudes activadas (píldoras pulsadas) en la gráfica de un sensor, por
/// (estación, sensor). Vacío por defecto: la tarjeta abre con las píldoras y
/// sus valores actuales, y un sensor solo muestra gráfica cuando se activa
/// alguna de sus magnitudes.
final sensorActiveChannelsProvider =
    StateProvider.family<Set<String>, (String gatewayId, String sensorKey)>((ref, key) => const {});

/// Histórico de un canal (agregación `average`) para el rango de SU
/// tarjeta — reutiliza `ReadingsApi.history` ya existente
/// (readings/application), solo añade la clave compuesta (organización +
/// canal + rango). La organización es la de [stationOrganizationIdProvider]:
/// null para un miembro.
final stationChannelHistoryProvider = FutureProvider.autoDispose
    .family<List<HistoryPoint>, (String? organizationId, String channelId, HistoryRange range)>((ref, key) {
  final (organizationId, channelId, range) = key;
  final to = DateTime.now().toUtc();
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: to.subtract(range.span),
        to: to,
        granularity: range.granularity,
        organizationId: organizationId,
      );
});

/// Histórico de un canal "de acumulados" (lluvia) para [AccumulatedChart] —
/// deliberadamente NO usa `HistoryRangeX.granularity` (pensada para las
/// líneas): 1 día/2 días necesitan el dato en crudo (para agrupar por
/// franjas de 6h en hora local, `AccumulatedChart._buildSlots`) y
/// semana/mes/2 meses necesitan `daily` siempre (acumulado por día, pedido
/// explícito — no `hourly` para semana como sí usan las líneas).
final stationAccumulatedHistoryProvider = FutureProvider.autoDispose
    .family<List<HistoryPoint>, (String? organizationId, String channelId, HistoryRange range)>((ref, key) {
  final (organizationId, channelId, range) = key;
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
          organizationId: organizationId,
        );
  }

  final to = DateTime.now().toUtc();
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: to.subtract(range.span),
        to: to,
        granularity: 'daily',
        organizationId: organizationId,
      );
});
