import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../directory/data/directory_models.dart';
import '../application/stations_controller.dart';
import 'station_card.dart';

/// Pantalla principal de datos en vivo (BACKLOG.md #30) — reemplaza a
/// Instalaciones como aterrizaje de un usuario normal de organización.
/// Barra lateral de selección (agrupada por Finca, mockup original:
/// "Estaciones seleccionadas: N") + panel principal con la tarjeta de cada
/// estación marcada, cada una independiente (su propio rango de gráfica y
/// sus propios canales activados).
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateways = ref.watch(allGatewaysProvider);
    // Sin nombres (aún cargando, o si fallan) el listado sigue funcionando:
    // los grupos salen como "Sin finca asignada".
    final installationNames = ref.watch(stationGroupNamesProvider).valueOrNull ?? const <String, String>{};
    final selected = ref.watch(selectedGatewayIdsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(allGatewaysProvider);
              ref.invalidate(stationGroupNamesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(allGatewaysProvider.future),
        child: gateways.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text('Todavía no hay estaciones dadas de alta.', textAlign: TextAlign.center),
              );
            }
            final sidebar = _StationSelectionList(gateways: items, installationNames: installationNames);
            final content = _SelectedStationsPanel(gateways: items, selected: selected);

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 240, child: sidebar),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(height: 280, child: sidebar),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            );
          },
          error: (error, _) => Center(child: Text('No se pudieron cargar las estaciones.\n$error')),
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
  final Map<String, String> installationNames;

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
      ..sort((a, b) => (installationNames[a] ?? a).compareTo(installationNames[b] ?? b));

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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          installationNames[installationId] ?? 'Sin finca asignada',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
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
            child: Text('No hay estaciones seleccionadas.', textAlign: TextAlign.center),
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
