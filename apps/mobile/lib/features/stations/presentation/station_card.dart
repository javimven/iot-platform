import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/channel_type_labels.dart';
import '../../readings/application/reading_history_controller.dart';
import '../application/stations_controller.dart';
import '../data/gateway_status_labels.dart';
import 'accumulated_chart.dart';
import 'combined_station_chart.dart';

/// Tarjeta de una Estación en la pantalla principal (BACKLOG.md #30):
/// estado + último dato → píldoras de canal (valor actual, activable) →
/// gráfica combinada del/de los canal(es) activado(s) con selector de rango.
class StationCard extends ConsumerWidget {
  const StationCard({required this.gateway, super.key});

  final Gateway gateway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestReadings = ref.watch(gatewayLatestReadingsProvider(gateway.id));
    final activeChannels = ref.watch(effectiveActiveChannelsProvider(gateway.id));
    final range = ref.watch(stationChartRangeProvider(gateway.id));
    final minimized = ref.watch(stationChartMinimizedProvider(gateway.id));
    final (statusLabel, statusTone) = GatewayStatusLabels.forStatus(gateway.status);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(gateway.name, style: Theme.of(context).textTheme.titleMedium),
              ),
              StatusChip(label: statusLabel, tone: statusTone),
              IconButton(
                icon: Icon(minimized ? Icons.expand_more : Icons.expand_less),
                tooltip: minimized ? 'Mostrar gráfica' : 'Minimizar gráfica',
                onPressed: () =>
                    ref.read(stationChartMinimizedProvider(gateway.id).notifier).state = !minimized,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quitar estación',
                onPressed: () {
                  final updated = {...ref.read(selectedGatewayIdsProvider)}..remove(gateway.id);
                  ref.read(selectedGatewayIdsProvider.notifier).state = updated;
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            gateway.lastSeenAt == null ? 'Sin datos todavía' : 'Último dato: ${_formatDate(gateway.lastSeenAt!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          latestReadings.when(
            data: (readings) => _ChannelPills(
              gatewayId: gateway.id,
              readings: readings,
              activeChannels: activeChannels,
            ),
            error: (error, _) => Text('No se pudieron cargar los datos.\n$error'),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          if (activeChannels.isEmpty || minimized)
            const SizedBox.shrink() // Sin canales todavía (ya lo dice _ChannelPills) o minimizada a mano.
          else ...[
            const SizedBox(height: 12),
            SegmentedButton<HistoryRange>(
              segments: HistoryRange.values.map((r) => ButtonSegment(value: r, label: Text(r.label))).toList(),
              selected: {range},
              onSelectionChanged: (selection) =>
                  ref.read(stationChartRangeProvider(gateway.id).notifier).state = selection.first,
            ),
            const SizedBox(height: 8),
            _StationChart(gatewayId: gateway.id, activeChannels: activeChannels, range: range),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ChannelPills extends ConsumerWidget {
  const _ChannelPills({required this.gatewayId, required this.readings, required this.activeChannels});

  final String gatewayId;
  final List<LatestReading> readings;
  final Set<String> activeChannels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (readings.isEmpty) {
      return const Text('Esta estación todavía no ha reportado ningún canal.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: readings.map((r) {
        final label = ChannelTypeLabels.labelFor(r.channelTypeCode);
        final unit = ChannelTypeLabels.unitFor(r.channelTypeCode);
        return FilterChip(
          label: Text('$label: ${r.value.toStringAsFixed(1)} $unit'),
          selected: activeChannels.contains(r.channelId),
          onSelected: (checked) {
            // Parte del conjunto EFECTIVO (incluye el primer canal
            // preseleccionado por defecto), no del manual en crudo — si no,
            // tocar una segunda píldora perdería la preselección implícita
            // de la primera en vez de añadirse a ella.
            final updated = {...ref.read(effectiveActiveChannelsProvider(gatewayId))};
            checked ? updated.add(r.channelId) : updated.remove(r.channelId);
            ref.read(stationActiveChannelsProvider(gatewayId).notifier).state = updated;
          },
        );
      }).toList(),
    );
  }
}

/// Reúne el histórico de cada canal activado en la gráfica que le
/// corresponde — [CombinedStationChart] (línea, agregación `average`,
/// varios canales combinables) o [AccumulatedChart] (barras por franja,
/// agregación `sum`, uno por canal, nunca combinado con los de línea:
/// BACKLOG.md #30, no tiene sentido visual mezclar una magnitud continua
/// con una acumulada). Colores fijos por posición (no por orden de
/// activación), para que un canal no cambie de color si se desactiva y
/// reactiva otro antes que él.
class _StationChart extends ConsumerWidget {
  const _StationChart({required this.gatewayId, required this.activeChannels, required this.range});

  final String gatewayId;
  final Set<String> activeChannels;
  final HistoryRange range;

  static const _palette = [AppColors.chartIndigo, AppColors.chartRose];
  static const _paletteDark = [AppColors.chartIndigoDark, AppColors.chartRoseDark];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestReadings = ref.watch(gatewayLatestReadingsProvider(gatewayId));
    final organizationId = ref.watch(stationOrganizationIdProvider(gatewayId));
    return latestReadings.when(
      data: (readings) {
        final byChannelId = {for (final r in readings) r.channelId: r};
        final channelIds = activeChannels.where(byChannelId.containsKey).toList()..sort();
        final lineChannelIds = channelIds
            .where((id) => ChannelTypeLabels.aggregationFor(byChannelId[id]!.channelTypeCode) != 'sum')
            .toList();
        final sumChannelIds = channelIds
            .where((id) => ChannelTypeLabels.aggregationFor(byChannelId[id]!.channelTypeCode) == 'sum')
            .toList();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final palette = isDark ? _paletteDark : _palette;
        final defaultColor = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;

        final lineHistories = [
          for (final channelId in lineChannelIds)
            ref.watch(stationChannelHistoryProvider((organizationId, channelId, range))),
        ];
        final sumHistories = [
          for (final channelId in sumChannelIds)
            ref.watch(stationAccumulatedHistoryProvider((organizationId, channelId, range))),
        ];
        final allHistories = [...lineHistories, ...sumHistories];
        if (allHistories.any((h) => h.isLoading)) {
          return const Center(child: CircularProgressIndicator());
        }
        final firstError = allHistories.indexWhere((h) => h.hasError);
        if (firstError != -1) {
          return Text('No se pudo cargar el histórico.\n${allHistories[firstError].error}');
        }

        final lineSeries = [
          for (var i = 0; i < lineChannelIds.length; i++)
            ChannelSeries(
              channelId: lineChannelIds[i],
              label: ChannelTypeLabels.labelFor(byChannelId[lineChannelIds[i]]!.channelTypeCode),
              unit: ChannelTypeLabels.unitFor(byChannelId[lineChannelIds[i]]!.channelTypeCode),
              points: lineHistories[i].value ?? const [],
              color: i < palette.length ? palette[i] : defaultColor,
            ),
        ];

        return Column(
          children: [
            if (lineSeries.isNotEmpty)
              SizedBox(height: 220, child: CombinedStationChart(series: lineSeries, range: range)),
            for (var i = 0; i < sumChannelIds.length; i++) ...[
              if (lineSeries.isNotEmpty || i > 0) const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: AccumulatedChart(
                  label: ChannelTypeLabels.labelFor(byChannelId[sumChannelIds[i]]!.channelTypeCode),
                  unit: ChannelTypeLabels.unitFor(byChannelId[sumChannelIds[i]]!.channelTypeCode),
                  color: i < palette.length ? palette[i] : defaultColor,
                  rawPoints: sumHistories[i].value ?? const [],
                  range: range,
                ),
              ),
            ],
          ],
        );
      },
      error: (error, _) => Text('No se pudo cargar el histórico.\n$error'),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
