import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../application/stations_controller.dart';
import '../application/station_detail_controller.dart';
import 'station_detail_screen.dart';
import 'station_notices.dart';
import 'station_summary_list.dart';

/// Pantalla principal de datos en vivo (BACKLOG.md #30) — reemplaza a
/// Instalaciones como aterrizaje de un usuario normal de organización.
/// El resumen de todas las estaciones (BACKLOG.md #49, mejora B) en cualquier
/// tamaño de pantalla, sin paso de selección; si solo hay una, directamente su
/// pantalla. La lista para marcar estaciones y la tarjeta de escritorio se
/// quitaron el 2026-09-18: el usuario prefiere esta vista también en el
/// ordenador.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateways = ref.watch(allGatewaysProvider);
    // Sin nombres (aún cargando, o si fallan) el listado sigue funcionando:
    // los grupos salen como "Sin finca asignada".
    final installationNames = ref.watch(stationGroupNamesProvider).valueOrNull ?? const <String, StationGroupName>{};
    // Una sola estación: nada que elegir, se abre directamente.
    final onlyStation = gateways.valueOrNull?.length == 1 ? gateways.valueOrNull!.single : null;
    if (onlyStation != null) {
      return StationDetailScreen(gatewayId: onlyStation.id);
    }

    Future<void> refreshAll() async {
      refreshStationData(ref);
      await ref.read(allGatewaysProvider.future);
    }

    return StationsAutoRefresh(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estaciones'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: refreshAll,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: refreshAll,
          child: gateways.when(
            data: (items) {
              if (items.isEmpty) {
                return const _Message(
                  title: 'Aún no hay estaciones',
                  detail: 'Cuando se dé de alta una en Infraestructura, aparecerá aquí.',
                );
              }
              return StationSummaryList(gateways: items, groupNames: installationNames);
            },
            error: (error, _) => _Message(
              title: 'No se han podido cargar las estaciones',
              detail: 'Comprueba la conexión y vuelve a intentarlo.',
              technicalDetail: '$error',
              onRetry: () {
                ref.invalidate(allGatewaysProvider);
                ref.invalidate(stationGroupNamesProvider);
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}

/// Estado vacío o de error de la pantalla: qué pasa, qué hacer y, si hay
/// error, el detalle técnico en pequeño para poder diagnosticarlo.
class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.technicalDetail, this.onRetry});

  final String title;
  final String detail;
  final String? technicalDetail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dentro de un ListView para que "tirar para actualizar" funcione también aquí.
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(detail, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
              child: AppButton(
                  label: 'Reintentar', icon: Icons.refresh, variant: AppButtonVariant.secondary, onPressed: onRetry)),
        ],
        if (technicalDetail != null) ...[
          const SizedBox(height: 16),
          Text(
            technicalDetail!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
