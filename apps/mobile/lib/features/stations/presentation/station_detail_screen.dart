import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/reading_format.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/widgets/app_shell.dart';
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
import 'station_health_icons.dart';
import 'station_notices.dart';

/// Pantalla de una estación (BACKLOG.md #49, mejora C), pensada para el móvil:
/// un sensor cada vez en pestañas, sus magnitudes como cifras grandes que
/// activan o quitan su gráfica, y la magnitud principal ya dibujada al entrar.
/// Con el teléfono girado, solo la gráfica (mejora E). Avisa si la estación no
/// envía o envía sin datos de sensores, y se refresca sola (mejora F).
class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({required this.gatewayId, super.key});

  final String gatewayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(stationByIdProvider(gatewayId));

    return StationsAutoRefresh(
      child: station.when(
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
      ),
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
        // Batería y cobertura de la estación van como iconos en la barra de
        // arriba, no como un sensor con su pestaña.
        final groups = [
          for (final g in groupReadingsBySensor(items))
            if (!isStationHealthGroup(g)) g,
        ];
        final health = [StationHealthIcons(readings: items, showDetailOnTap: true), const SizedBox(width: 8)];
        final dataState = stationDataState(gateway, items);
        if (groups.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: title(), actions: health),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (dataState.state != StationDataState.ok) ...[
                  StationDataNotice(state: dataState.state, since: dataState.since),
                  const SizedBox(height: 12),
                ],
                const Text('Esta estación aún no ha enviado datos de sensores. Aparecerán aquí con su próximo envío.'),
              ],
            ),
          );
        }
        final selected = ref.watch(detailSelectedSensorProvider(gateway.id)).clamp(0, groups.length - 1);

        final aliveAt = stationAliveAt(gateway, items);
        if (isPhoneLandscape(MediaQuery.sizeOf(context))) {
          return _FullScreenChart(gateway: gateway, groups: groups, selected: selected, aliveAt: aliveAt);
        }

        return DefaultTabController(
          length: groups.length,
          initialIndex: selected,
          child: Scaffold(
            appBar: AppBar(
              title: title(),
              actions: health,
              bottom: groups.length < 2
                  ? null
                  : TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      onTap: (index) => ref.read(detailSelectedSensorProvider(gateway.id).notifier).state = index,
                      tabs: [for (final g in groups) Tab(text: g.label)],
                    ),
            ),
            // Sin deslizar entre sensores: el arrastre horizontal es para leer
            // la gráfica; se cambia de sensor tocando su pestaña.
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final g in groups)
                  _SensorPage(gateway: gateway, group: g, dataState: dataState, aliveAt: aliveAt),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lo que necesitan las gráficas de un sensor: qué magnitudes están activas, en
/// qué orden y con qué estilo, y el rango.
class _SensorChartModel {
  _SensorChartModel(WidgetRef ref, BuildContext context, this.gateway, this.group)
      : key = (gateway.id, group.key),
        ordered = readingsByPriority(group) {
    active = effectiveDetailChannels(group, ref.watch(detailActiveChannelsProvider(key)));
    range = ref.watch(sensorChartRangeProvider(key));
    organizationId = ref.watch(stationOrganizationIdProvider(gateway.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    styles = {for (var i = 0; i < ordered.length; i++) ordered[i].channelId: seriesStyle(i, isDark: isDark)};
    final activeReadings = [for (final r in ordered) if (active.contains(r.channelId)) r];
    lineReadings = [
      for (final r in activeReadings)
        if (ChannelTypeLabels.aggregationFor(r.channelTypeCode) != 'sum') r,
    ];
    sumReadings = [
      for (final r in activeReadings)
        if (ChannelTypeLabels.aggregationFor(r.channelTypeCode) == 'sum') r,
    ];
  }

  final Gateway gateway;
  final SensorReadings group;
  final (String, String) key;
  final List<LatestReading> ordered;
  late final Set<String> active;
  late final HistoryRange range;
  late final String? organizationId;
  late final Map<String, ({Color color, List<int>? dash})> styles;
  late final List<LatestReading> lineReadings;
  late final List<LatestReading> sumReadings;

  void selectRange(WidgetRef ref, HistoryRange value) {
    ref.read(sensorChartRangeProvider(key).notifier).state = value;
    ref.read(chartCrosshairProvider(key).notifier).state = null;
  }
}

class _RangeSelector extends ConsumerWidget {
  const _RangeSelector({required this.model});

  final _SensorChartModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<HistoryRange>(
      segments: [for (final r in HistoryRange.values) ButtonSegment(value: r, label: Text(r.shortLabel))],
      selected: {model.range},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => model.selectRange(ref, selection.first),
    );
  }
}

class _SensorPage extends ConsumerWidget {
  const _SensorPage({required this.gateway, required this.group, required this.dataState, required this.aliveAt});

  final Gateway gateway;
  final SensorReadings group;
  final ({StationDataState state, DateTime? since}) dataState;
  final DateTime? aliveAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = _SensorChartModel(ref, context, gateway, group);
    final theme = Theme.of(context);
    final soft = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    void toggle(LatestReading reading) {
      ref.read(detailActiveChannelsProvider(model.key).notifier).state =
          toggleDetailChannel(model.active, reading.channelId);
    }

    return RefreshIndicator(
      onRefresh: () async => refreshStationData(ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.list(children: [
          if (dataState.state != StationDataState.ok) ...[
            StationDataNotice(state: dataState.state, since: dataState.since),
            const SizedBox(height: 12),
          ],
          if (group.externalIdentifier != null && group.externalIdentifier != group.label)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${group.label}, conectado en ${group.externalIdentifier}', style: soft),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              // Dos columnas como mucho: con tres en un móvil los nombres se cortan.
              final columns = model.ordered.length == 1 ? 1 : 2;
              const gap = 8.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final r in model.ordered)
                    SizedBox(
                      width: width,
                      child: _MagnitudeToggle(
                        reading: r,
                        selected: model.active.contains(r.channelId),
                        stale: isReadingStale(r, aliveAt),
                        color: model.styles[r.channelId]!.color,
                        dash: model.styles[r.channelId]!.dash,
                        onTap: () => toggle(r),
                      ),
                    ),
                ],
              );
            },
          ),
              const SizedBox(height: 16),
              _RangeSelector(model: model),
              const SizedBox(height: 8),
            ]),
          ),
          SliverPersistentHeader(pinned: true, delegate: _PinnedReadout(model: model)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(children: [
              if (model.lineReadings.isNotEmpty) _LineCharts(model: model, showReadout: false),
              for (final r in model.sumReadings) ...[
                const SizedBox(height: 16),
                _AccumulatedFor(model: model, reading: r),
              ],
              if (MediaQuery.sizeOf(context).shortestSide < 600) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.screen_rotation, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(child: Text('Gira el móvil para verla a pantalla completa', style: soft)),
                  ],
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Teléfono girado: la gráfica lo más grande posible, con su lectura al
/// arrastrar el dedo, y nada más (BACKLOG.md #49, mejora E). Los ajustes
/// —sensor, rango y magnitudes— se abren en una hoja desde abajo con el botón
/// de la esquina (2026-09-18, elección del usuario): antes ocupaban cabecera y
/// columna fijas, y antes de eso ni se podían cambiar sin poner el móvil
/// derecho.
class _FullScreenChart extends ConsumerWidget {
  const _FullScreenChart({
    required this.gateway,
    required this.groups,
    required this.selected,
    required this.aliveAt,
  });

  final Gateway gateway;
  final List<SensorReadings> groups;
  final int selected;
  final DateTime? aliveAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = _SensorChartModel(ref, context, gateway, groups[selected]);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 52, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReadoutBar(model: model),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final count = model.lineReadings.length;
                        // Cabecera de cada gráfica (~24) + separaciones.
                        final overhead = 8 + count * 24 + (count > 1 ? (count - 1) * 12 : 0);
                        final height =
                            count == 0 ? 0.0 : ((constraints.maxHeight - overhead) / count).clamp(110.0, 600.0);
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (count > 0) _LineCharts(model: model, chartHeight: height, showReadout: false),
                              for (final r in model.sumReadings) ...[
                                const SizedBox(height: 12),
                                _AccumulatedFor(
                                  model: model,
                                  reading: r,
                                  height: count == 0 ? constraints.maxHeight - 12 : 200,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // El botón se queda a la vista en el hueco que le deja la gráfica.
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.tune),
                tooltip: 'Sensor, rango y magnitudes',
                onPressed: () => _abrirAjustes(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirAjustes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          // Dentro de la hoja se sigue el sensor elegido: cambiarlo redibuja
          // tanto la hoja como la gráfica de detrás.
          final elegido = ref.watch(detailSelectedSensorProvider(gateway.id)).clamp(0, groups.length - 1);
          return _ChartSettingsSheet(
            gateway: gateway,
            groups: groups,
            selected: elegido,
            aliveAt: aliveAt,
            model: _SensorChartModel(ref, context, gateway, groups[elegido]),
          );
        },
      ),
    );
  }
}

/// Ajustes de la gráfica con el móvil girado, en una hoja desde abajo: qué
/// sensor, qué rango y qué magnitudes. Los mismos controles que en vertical,
/// repartidos a lo ancho, que es lo que sobra girado.
class _ChartSettingsSheet extends ConsumerWidget {
  const _ChartSettingsSheet({
    required this.gateway,
    required this.groups,
    required this.selected,
    required this.aliveAt,
    required this.model,
  });

  final Gateway gateway;
  final List<SensorReadings> groups;
  final int selected;
  final DateTime? aliveAt;
  final _SensorChartModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final titulo = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(gateway.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (groups.length > 1) ...[
          const SizedBox(height: 8),
          Text('Sensor', style: titulo),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < groups.length; i++)
                ChoiceChip(
                  label: Text(groups[i].label),
                  selected: i == selected,
                  onSelected: (_) => ref.read(detailSelectedSensorProvider(gateway.id).notifier).state = i,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text('Rango', style: titulo),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _RangeSelector(model: model),
        ),
        const SizedBox(height: 8),
        Text('Magnitudes', style: titulo),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in model.ordered)
              SizedBox(
                width: 160,
                child: _MagnitudeToggle(
                  reading: r,
                  selected: model.active.contains(r.channelId),
                  stale: isReadingStale(r, aliveAt),
                  color: model.styles[r.channelId]!.color,
                  dash: model.styles[r.channelId]!.dash,
                  compact: true,
                  onTap: () => ref.read(detailActiveChannelsProvider(model.key).notifier).state =
                      toggleDetailChannel(model.active, r.channelId),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Cifra grande de una magnitud que a la vez activa o quita su gráfica. Activa,
/// lleva el borde y la muestra de trazo de su serie; además del color, lo dice
/// el lector de pantalla. Si el sensor ha dejado de contestar, lo avisa debajo.
class _MagnitudeToggle extends StatelessWidget {
  const _MagnitudeToggle({
    required this.reading,
    required this.selected,
    required this.stale,
    required this.color,
    required this.dash,
    required this.onTap,
    this.compact = false,
  });

  final LatestReading reading;
  final bool selected;
  final bool stale;
  final Color color;
  final List<int>? dash;
  final VoidCallback onTap;

  /// Versión estrecha para la columna del móvil girado: la cifra más pequeña
  /// y sin el aviso de dato atrasado, que ahí no cabe (va en vertical).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = ChannelTypeLabels.labelFor(reading.channelTypeCode);
    final unit = ChannelTypeLabels.unitFor(reading.channelTypeCode);
    final staleText = stale ? ', sin datos desde ${formatAgo(reading.tsOrigin)}' : '';

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${formatReading(reading.value)} $unit, ${selected ? 'gráfica visible' : 'gráfica oculta'}$staleText',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 48 : 72),
          padding: compact ? const EdgeInsets.fromLTRB(8, 6, 8, 6) : const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 2 : 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatReading(reading.value),
                      style: (compact ? theme.textTheme.titleMedium : theme.textTheme.headlineSmall)?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                        color: stale ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (stale && !compact) StaleReadingNote(since: reading.tsOrigin),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las series de las magnitudes activas, ya cargadas para el rango: las usan
/// las gráficas y la barra de lectura, que van en sitios distintos de la
/// pantalla pero leen lo mismo.
List<StackedSeries> _seriesFor(WidgetRef ref, BuildContext context, _SensorChartModel model) {
  final readings = model.lineReadings;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    for (final r in readings)
      StackedSeries(
        channelId: r.channelId,
        label: ChannelTypeLabels.labelFor(r.channelTypeCode),
        unit: ChannelTypeLabels.unitFor(r.channelTypeCode),
        points: ref.watch(stationChannelHistoryProvider((model.organizationId, r.channelId, model.range))).valueOrNull ??
            const [],
        color: model.styles[r.channelId]?.color ?? seriesStyle(0, isDark: isDark).color,
        dash: model.styles[r.channelId]?.dash,
      ),
  ];
}

/// Barra con la hora marcada y el valor de cada magnitud en ese instante. Va
/// fija arriba: al bajar por la pantalla no se pierde de vista (2026-09-18,
/// petición del usuario).
class _ReadoutBar extends ConsumerWidget {
  const _ReadoutBar({required this.model});

  static const height = 44.0;

  final _SensorChartModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(bottom: 6),
      color: theme.colorScheme.surface,
      child: ChannelReadout(
        series: _seriesFor(ref, context, model),
        crosshairMillis: ref.watch(chartCrosshairProvider(model.key)),
        range: model.range,
        maxLines: 2,
      ),
    );
  }
}

/// La barra de lectura, clavada arriba mientras se baja por la pantalla.
class _PinnedReadout extends SliverPersistentHeaderDelegate {
  const _PinnedReadout({required this.model});

  final _SensorChartModel model;

  @override
  double get minExtent => _ReadoutBar.height;

  @override
  double get maxExtent => _ReadoutBar.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => _ReadoutBar(model: model);

  @override
  bool shouldRebuild(_PinnedReadout oldDelegate) => true;
}

class _LineCharts extends ConsumerWidget {
  const _LineCharts({required this.model, this.chartHeight, this.showReadout = true});

  final _SensorChartModel model;
  final double? chartHeight;
  final bool showReadout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = model.lineReadings;
    final histories = [
      for (final r in readings)
        ref.watch(stationChannelHistoryProvider((model.organizationId, r.channelId, model.range))),
    ];
    if (histories.any((h) => h.isLoading && !h.hasValue)) {
      return SizedBox(height: chartHeight ?? 240, child: const Center(child: CircularProgressIndicator()));
    }
    final failed = histories.indexWhere((h) => h.hasError);
    if (failed != -1) {
      return RetryMessage(
        message: 'No se ha podido cargar la gráfica.',
        technicalDetail: '${histories[failed].error}',
        onRetry: () {
          for (final r in readings) {
            ref.invalidate(stationChannelHistoryProvider((model.organizationId, r.channelId, model.range)));
          }
        },
      );
    }

    return StackedChannelCharts(
      range: model.range,
      chartHeight: chartHeight,
      showReadout: showReadout,
      crosshairMillis: ref.watch(chartCrosshairProvider(model.key)),
      onCrosshair: (millis) => ref.read(chartCrosshairProvider(model.key).notifier).state = millis,
      series: _seriesFor(ref, context, model),
    );
  }
}

class _AccumulatedFor extends ConsumerWidget {
  const _AccumulatedFor({required this.model, required this.reading, this.height = 220});

  final _SensorChartModel model;
  final LatestReading reading;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = stationAccumulatedHistoryProvider((model.organizationId, reading.channelId, model.range));
    final history = ref.watch(provider);
    return history.when(
      loading: () => SizedBox(height: height, child: const Center(child: CircularProgressIndicator())),
      error: (error, _) => RetryMessage(
        message: 'No se ha podido cargar la gráfica.',
        technicalDetail: '$error',
        onRetry: () => ref.invalidate(provider),
      ),
      data: (points) => SizedBox(
        height: height,
        child: AccumulatedChart(
          label: ChannelTypeLabels.labelFor(reading.channelTypeCode),
          unit: ChannelTypeLabels.unitFor(reading.channelTypeCode),
          color: model.styles[reading.channelId]!.color,
          rawPoints: points,
          range: model.range,
        ),
      ),
    );
  }
}
