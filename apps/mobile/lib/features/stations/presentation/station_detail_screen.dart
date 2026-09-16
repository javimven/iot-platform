import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/reading_format.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/widgets/retry_message.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/channel_type_labels.dart';
import '../../readings/application/reading_history_controller.dart';
import '../application/sensor_groups.dart';
import '../application/station_detail_controller.dart';
import '../application/stations_controller.dart';
import '../data/gateway_status_labels.dart';
import 'accumulated_chart.dart';
import 'series_style.dart';
import 'stacked_channel_charts.dart';

/// Pantalla de una estación (BACKLOG.md #49, mejora C), pensada para el móvil:
/// un sensor cada vez en pestañas, sus magnitudes como cifras grandes que
/// activan o quitan su gráfica, y la magnitud principal ya dibujada al entrar.
class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({required this.gatewayId, super.key});

  final String gatewayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(stationByIdProvider(gatewayId));

    return station.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Estación')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: RetryMessage(
            message: 'No se ha podido cargar la estación.',
            technicalDetail: '$error',
            onRetry: () => ref.invalidate(allGatewaysProvider),
          ),
        ),
      ),
      data: (gateway) => gateway == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Estación')),
              body: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Esta estación ya no existe o no tienes acceso a ella.'),
              ),
            )
          : _StationDetail(gateway: gateway),
    );
  }
}

class _StationDetail extends ConsumerWidget {
  const _StationDetail({required this.gateway});

  final Gateway gateway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(gatewayLatestReadingsProvider(gateway.id));
    final (statusLabel, _) = GatewayStatusLabels.forStatus(gateway.status);
    final lastSeen = gateway.lastSeenAt;
    final subtitle = lastSeen == null ? statusLabel : '$statusLabel, último dato ${formatAgo(lastSeen)}';
    final theme = Theme.of(context);

    Widget title() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(gateway.name, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );

    return readings.when(
      loading: () => Scaffold(appBar: AppBar(title: title()), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: title()),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: RetryMessage(
            message: 'No se han podido cargar los datos de esta estación.',
            technicalDetail: '$error',
            onRetry: () => ref.invalidate(gatewayLatestReadingsProvider(gateway.id)),
          ),
        ),
      ),
      data: (items) {
        final groups = groupReadingsBySensor(items);
        if (groups.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: title()),
            body: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Esta estación aún no ha enviado datos de sensores. Aparecerán aquí con su próximo envío.'),
            ),
          );
        }
        return DefaultTabController(
          length: groups.length,
          child: Scaffold(
            appBar: AppBar(
              title: title(),
              bottom: groups.length < 2
                  ? null
                  : TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [for (final g in groups) Tab(text: g.label)],
                    ),
            ),
            // Sin deslizar entre sensores: el arrastre horizontal es para leer
            // la gráfica; se cambia de sensor tocando su pestaña.
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final g in groups) _SensorPage(gateway: gateway, group: g)],
            ),
          ),
        );
      },
    );
  }
}

class _SensorPage extends ConsumerWidget {
  const _SensorPage({required this.gateway, required this.group});

  final Gateway gateway;
  final SensorReadings group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (gateway.id, group.key);
    final active = effectiveDetailChannels(group, ref.watch(detailActiveChannelsProvider(key)));
    final range = ref.watch(sensorChartRangeProvider(key));
    final organizationId = ref.watch(stationOrganizationIdProvider(gateway.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    final ordered = readingsByPriority(group);
    final styles = {
      for (var i = 0; i < ordered.length; i++) ordered[i].channelId: seriesStyle(i, isDark: isDark),
    };
    final activeReadings = [for (final r in ordered) if (active.contains(r.channelId)) r];
    final lineReadings = activeReadings.where((r) => ChannelTypeLabels.aggregationFor(r.channelTypeCode) != 'sum').toList();
    final sumReadings = activeReadings.where((r) => ChannelTypeLabels.aggregationFor(r.channelTypeCode) == 'sum').toList();

    void toggle(LatestReading reading) {
      final updated = {...active};
      updated.contains(reading.channelId) ? updated.remove(reading.channelId) : updated.add(reading.channelId);
      ref.read(detailActiveChannelsProvider(key).notifier).state = updated;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (group.externalIdentifier != null && group.externalIdentifier != group.label)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${group.label}, conectado en ${group.externalIdentifier}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Dos columnas como mucho: con tres en un móvil los nombres se cortan.
            final columns = ordered.length == 1 ? 1 : 2;
            const gap = 8.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final r in ordered)
                  SizedBox(
                    width: width,
                    child: _MagnitudeToggle(
                      reading: r,
                      selected: active.contains(r.channelId),
                      color: styles[r.channelId]!.color,
                      dash: styles[r.channelId]!.dash,
                      onTap: () => toggle(r),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (activeReadings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Toca una magnitud para ver su gráfica.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else ...[
          SegmentedButton<HistoryRange>(
            segments: [for (final r in HistoryRange.values) ButtonSegment(value: r, label: Text(r.shortLabel))],
            selected: {range},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              ref.read(sensorChartRangeProvider(key).notifier).state = selection.first;
              ref.read(chartCrosshairProvider(key).notifier).state = null;
            },
          ),
          const SizedBox(height: 16),
          if (lineReadings.isNotEmpty)
            _LineCharts(
              gateway: gateway,
              chartKey: key,
              organizationId: organizationId,
              readings: lineReadings,
              styles: styles,
              range: range,
            ),
          for (final r in sumReadings) ...[
            const SizedBox(height: 16),
            _AccumulatedFor(organizationId: organizationId, reading: r, color: styles[r.channelId]!.color, range: range),
          ],
        ],
      ],
    );
  }
}

/// Cifra grande de una magnitud que a la vez activa o quita su gráfica. Activa,
/// lleva el borde y la muestra de trazo de su serie; además del color, lo dice
/// el lector de pantalla.
class _MagnitudeToggle extends StatelessWidget {
  const _MagnitudeToggle({
    required this.reading,
    required this.selected,
    required this.color,
    required this.dash,
    required this.onTap,
  });

  final LatestReading reading;
  final bool selected;
  final Color color;
  final List<int>? dash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = ChannelTypeLabels.labelFor(reading.channelTypeCode);
    final unit = ChannelTypeLabels.unitFor(reading.channelTypeCode);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${formatReading(reading.value)} $unit, ${selected ? 'gráfica visible' : 'gráfica oculta'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
            border: Border.all(color: selected ? color : theme.colorScheme.outline, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selected) ...[SeriesSwatch(color: color, dash: dash, width: 14), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatReading(reading.value),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineCharts extends ConsumerWidget {
  const _LineCharts({
    required this.gateway,
    required this.chartKey,
    required this.organizationId,
    required this.readings,
    required this.styles,
    required this.range,
  });

  final Gateway gateway;
  final (String, String) chartKey;
  final String? organizationId;
  final List<LatestReading> readings;
  final Map<String, ({Color color, List<int>? dash})> styles;
  final HistoryRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histories = [
      for (final r in readings) ref.watch(stationChannelHistoryProvider((organizationId, r.channelId, range))),
    ];
    if (histories.any((h) => h.isLoading && !h.hasValue)) {
      return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
    }
    final failed = histories.indexWhere((h) => h.hasError);
    if (failed != -1) {
      return RetryMessage(
        message: 'No se ha podido cargar la gráfica.',
        technicalDetail: '${histories[failed].error}',
        onRetry: () {
          for (final r in readings) {
            ref.invalidate(stationChannelHistoryProvider((organizationId, r.channelId, range)));
          }
        },
      );
    }

    return StackedChannelCharts(
      range: range,
      crosshairMillis: ref.watch(chartCrosshairProvider(chartKey)),
      onCrosshair: (millis) => ref.read(chartCrosshairProvider(chartKey).notifier).state = millis,
      series: [
        for (var i = 0; i < readings.length; i++)
          StackedSeries(
            channelId: readings[i].channelId,
            label: ChannelTypeLabels.labelFor(readings[i].channelTypeCode),
            unit: ChannelTypeLabels.unitFor(readings[i].channelTypeCode),
            points: histories[i].valueOrNull ?? const [],
            color: styles[readings[i].channelId]!.color,
            dash: styles[readings[i].channelId]!.dash,
          ),
      ],
    );
  }
}

class _AccumulatedFor extends ConsumerWidget {
  const _AccumulatedFor({required this.organizationId, required this.reading, required this.color, required this.range});

  final String? organizationId;
  final LatestReading reading;
  final Color color;
  final HistoryRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(stationAccumulatedHistoryProvider((organizationId, reading.channelId, range)));
    return history.when(
      loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
      error: (error, _) => RetryMessage(
        message: 'No se ha podido cargar la gráfica.',
        technicalDetail: '$error',
        onRetry: () => ref.invalidate(stationAccumulatedHistoryProvider((organizationId, reading.channelId, range))),
      ),
      data: (points) => SizedBox(
        height: 220,
        child: AccumulatedChart(
          label: ChannelTypeLabels.labelFor(reading.channelTypeCode),
          unit: ChannelTypeLabels.unitFor(reading.channelTypeCode),
          color: color,
          rawPoints: points,
          range: range,
        ),
      ),
    );
  }
}
