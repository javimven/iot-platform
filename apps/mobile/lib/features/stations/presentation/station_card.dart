import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../directory/data/directory_models.dart';
import '../../readings/application/channel_type_labels.dart';
import '../../readings/application/reading_history_controller.dart';
import '../application/sensor_groups.dart';
import '../application/stations_controller.dart';
import '../data/gateway_status_labels.dart';
import 'accumulated_chart.dart';
import 'combined_station_chart.dart';

/// Tarjeta de una Estación en la pantalla principal (BACKLOG.md #30):
/// estado + último dato → selector de rango (común a la estación) → un
/// bloque por sensor, con las píldoras de sus magnitudes (valor actual,
/// activables) y su propia gráfica con las que estén activadas.
class StationCard extends ConsumerWidget {
  const StationCard({required this.gateway, super.key});

  final Gateway gateway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestReadings = ref.watch(gatewayLatestReadingsProvider(gateway.id));
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
                tooltip: minimized ? 'Mostrar gráficas' : 'Minimizar gráficas',
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
            data: (readings) {
              if (readings.isEmpty) {
                return const Text('Esta estación todavía no ha reportado ningún canal.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in groupReadingsBySensor(readings))
                    _SensorSection(gatewayId: gateway.id, group: group, minimized: minimized),
                ],
              );
            },
            error: (error, _) => Text('No se pudieron cargar los datos.\n$error'),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
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

/// Un sensor de la estación: su nombre y las píldoras de sus magnitudes con
/// el valor actual. Al activar alguna aparece debajo su gráfica, con el
/// selector de rango encima; sin ninguna activada, el sensor ocupa solo sus
/// píldoras. Minimizar la tarjeta oculta las gráficas abiertas, no las
/// píldoras.
class _SensorSection extends ConsumerWidget {
  const _SensorSection({required this.gatewayId, required this.group, required this.minimized});

  final String gatewayId;
  final SensorReadings group;
  final bool minimized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (gatewayId, group.key);
    final activeChannels = ref.watch(sensorActiveChannelsProvider(key));
    final range = ref.watch(sensorChartRangeProvider(key));
    final identifier = group.externalIdentifier;
    final title = identifier == null || identifier == group.label ? group.label : '${group.label} · $identifier';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.readings.map((r) {
              final label = ChannelTypeLabels.labelFor(r.channelTypeCode);
              final unit = ChannelTypeLabels.unitFor(r.channelTypeCode);
              return FilterChip(
                label: Text('$label: ${r.value.toStringAsFixed(1)} $unit'),
                selected: activeChannels.contains(r.channelId),
                onSelected: (checked) {
                  final updated = {...ref.read(sensorActiveChannelsProvider(key))};
                  checked ? updated.add(r.channelId) : updated.remove(r.channelId);
                  ref.read(sensorActiveChannelsProvider(key).notifier).state = updated;
                },
              );
            }).toList(),
          ),
          if (activeChannels.isNotEmpty && !minimized) ...[
            const SizedBox(height: 12),
            SegmentedButton<HistoryRange>(
              segments: HistoryRange.values.map((r) => ButtonSegment(value: r, label: Text(r.label))).toList(),
              selected: {range},
              onSelectionChanged: (selection) => ref.read(sensorChartRangeProvider(key).notifier).state = selection.first,
            ),
            const SizedBox(height: 8),
            _StationChart(
              gatewayId: gatewayId,
              channelOrder: [for (final r in group.readings) r.channelId],
              activeChannels: activeChannels,
              range: range,
            ),
          ],
        ],
      ),
    );
  }
}

/// Reúne el histórico de cada magnitud activada de un sensor en la gráfica
/// que le corresponde — [CombinedStationChart] (línea, agregación `average`,
/// varias magnitudes combinables) o [AccumulatedChart] (barras por franja,
/// agregación `sum`, una por magnitud, nunca combinada con las de línea:
/// BACKLOG.md #30, no tiene sentido visual mezclar una magnitud continua
/// con una acumulada). El color de cada magnitud sale de su posición entre
/// las del sensor ([channelOrder]), no del orden de activación, para que no
/// cambie de color al activar o quitar otra.
class _StationChart extends ConsumerWidget {
  const _StationChart({
    required this.gatewayId,
    required this.channelOrder,
    required this.activeChannels,
    required this.range,
  });

  final String gatewayId;
  final List<String> channelOrder;
  final Set<String> activeChannels;
  final HistoryRange range;

  static const _palette = [AppColors.chartIndigo, AppColors.chartRose, AppColors.chartOchre];
  static const _paletteDark = [AppColors.chartIndigoDark, AppColors.chartRoseDark, AppColors.chartOchreDark];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestReadings = ref.watch(gatewayLatestReadingsProvider(gatewayId));
    final organizationId = ref.watch(stationOrganizationIdProvider(gatewayId));
    return latestReadings.when(
      data: (readings) {
        final byChannelId = {for (final r in readings) r.channelId: r};
        final channelIds =
            channelOrder.where((id) => activeChannels.contains(id) && byChannelId.containsKey(id)).toList();
        final lineChannelIds = channelIds
            .where((id) => ChannelTypeLabels.aggregationFor(byChannelId[id]!.channelTypeCode) != 'sum')
            .toList();
        final sumChannelIds = channelIds
            .where((id) => ChannelTypeLabels.aggregationFor(byChannelId[id]!.channelTypeCode) == 'sum')
            .toList();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final palette = isDark ? _paletteDark : _palette;
        final defaultColor = isDark ? AppColors.inkSoftDark : AppColors.inkSoft;
        Color colorFor(String channelId) {
          final position = channelOrder.indexOf(channelId);
          return position < palette.length ? palette[position] : defaultColor;
        }

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
              color: colorFor(lineChannelIds[i]),
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
                  color: colorFor(sumChannelIds[i]),
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
