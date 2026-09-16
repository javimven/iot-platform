import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_shell.dart';
import '../../directory/data/directory_models.dart';
import '../application/stations_controller.dart';
import '../application/station_detail_controller.dart';
import 'station_card.dart';
import 'station_detail_screen.dart';
import 'station_summary_list.dart';

/// Pantalla principal de datos en vivo (BACKLOG.md #30) — reemplaza a
/// Instalaciones como aterrizaje de un usuario normal de organización.
/// En pantallas anchas, barra lateral de selección (agrupada por Finca,
/// mockup original: "Estaciones seleccionadas: N") + panel principal con la
/// tarjeta de cada estación marcada. En el móvil (BACKLOG.md #49, mejora B),
/// el resumen de todas las estaciones sin paso de selección, y si solo hay
/// una, directamente su pantalla.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateways = ref.watch(allGatewaysProvider);
    // Sin nombres (aún cargando, o si fallan) el listado sigue funcionando:
    // los grupos salen como "Sin finca asignada".
    final installationNames =
        ref.watch(stationGroupNamesProvider).valueOrNull ?? const <String, StationGroupName>{};
    final selected = ref.watch(selectedGatewayIdsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= compactShellBreakpoint;

    // Una sola estación en el móvil: nada que elegir, se abre directamente.
    final onlyStation = gateways.valueOrNull?.length == 1 ? gateways.valueOrNull!.single : null;
    if (!isWide && onlyStation != null) {
      return StationDetailScreen(gatewayId: onlyStation.id);
    }

    Future<void> refreshAll() async {
      ref.invalidate(stationGroupNamesProvider);
      ref.invalidate(gatewayLatestReadingsProvider);
      ref.invalidate(stationSparklineProvider);
      ref.invalidate(allGatewaysProvider);
      await ref.read(allGatewaysProvider.future);
    }

    return Scaffold(
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
            if (!isWide) {
              return StationSummaryList(gateways: items, groupNames: installationNames);
            }
            final sidebar = _StationSelectionList(gateways: items, installationNames: installationNames);
            final content = _SelectedStationsPanel(gateways: items, selected: selected);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: sidebar),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
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
    );
  }
}

/// Buscador + listado de selección, agrupado por Finca (mockup original:
/// "Listado de estaciones"). Cada grupo muestra el nombre de la finca como
/// cabecera — como pediste, si "Estación Norte" y "Estación Sur" son de la
/// misma finca, aparecen juntas debajo de su nombre.
class _StationSelectionList extends ConsumerWidget {
  const _StationSelectionList({required this.gateways, required this.installationNames});

  final List<Gateway> gateways;
  final Map<String, StationGroupName> installationNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(stationSearchQueryProvider);
    final selected = ref.watch(selectedGatewayIdsProvider);

    final filtered = query.trim().isEmpty
        ? gateways
        : gateways.where((g) => g.name.toLowerCase().contains(query.trim().toLowerCase())).toList();

    final byInstallation = <String, List<Gateway>>{};
    for (final g in filtered) {
      (byInstallation[g.installationId] ??= []).add(g);
    }
    final installationIds = byInstallation.keys.toList()
      ..sort((a, b) => _sortKey(installationNames[a], a).compareTo(_sortKey(installationNames[b], b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Busca una estación...',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => ref.read(stationSearchQueryProvider.notifier).state = value,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Ninguna estación coincide con la búsqueda.'),
                )
              : ListView(
                  children: [
                    for (final installationId in installationIds) ...[
                      _GroupHeader(name: installationNames[installationId]),
                      for (final gateway in byInstallation[installationId]!)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _StationSelectorBox(
                            gateway: gateway,
                            selected: selected.contains(gateway.id),
                            onTap: () {
                              final updated = {...selected};
                              selected.contains(gateway.id) ? updated.remove(gateway.id) : updated.add(gateway.id);
                              ref.read(selectedGatewayIdsProvider.notifier).state = updated;
                            },
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Caja seleccionable (en vez de una casilla con tick) — se remarca con
/// borde y fondo cuando está marcada, además del icono de check (el estado
/// nunca se codifica solo en color, mismo principio que `StatusChip`).
class _StationSelectorBox extends StatelessWidget {
  const _StationSelectorBox({required this.gateway, required this.selected, required this.onTap});

  final Gateway gateway;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        // Al menos 48 px de alto: se toca con el pulgar.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? colorScheme.primary : colorScheme.outline),
          color: selected ? colorScheme.primary.withValues(alpha: 0.1) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                gateway.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? colorScheme.primary : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SelectedStationsPanel extends StatelessWidget {
  const _SelectedStationsPanel({required this.gateways, required this.selected});

  final List<Gateway> gateways;
  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Estaciones seleccionadas: ${selected.length}', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Marca una estación en la lista para ver sus datos.', textAlign: TextAlign.center),
          )
        else
          for (final gateway in gateways.where((g) => selected.contains(g.id)))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StationCard(gateway: gateway),
            ),
      ],
    );
  }
}

/// Orden de los grupos: por organización (vista de plataforma) y luego finca.
String _sortKey(StationGroupName? name, String fallback) =>
    name == null ? '~$fallback' : '${name.organization ?? ''}\u0000${name.farm}';

/// Cabecera de un grupo: la finca y, debajo, la organización cuando la vista
/// mezcla varias.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name});

  final StationGroupName? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name?.farm ?? 'Sin finca asignada',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
          ),
          if (name?.organization != null)
            Text(name!.organization!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
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
          Center(child: AppButton(label: 'Reintentar', icon: Icons.refresh, variant: AppButtonVariant.secondary, onPressed: onRetry)),
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
