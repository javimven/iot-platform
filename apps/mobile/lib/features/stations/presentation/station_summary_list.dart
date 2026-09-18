import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/reading_format.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/retry_message.dart';
import '../../../core/widgets/status_chip.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/channel_type_labels.dart';
import '../../readings/data/reading_history_models.dart';
import '../application/sensor_groups.dart';
import '../application/station_detail_controller.dart';
import '../application/stations_controller.dart';
import '../data/gateway_status_labels.dart';
import 'station_notices.dart';

/// Resumen de todas las estaciones, lo primero que se ve en el móvil
/// (BACKLOG.md #49, mejora B): sin paso de marcar estaciones, cada una con la
/// magnitud principal de cada sensor, su tendencia de 24 h y si está enviando.
/// Toda la tarjeta abre la pantalla de la estación.
class StationSummaryList extends ConsumerWidget {
  const StationSummaryList({required this.gateways, required this.groupNames, super.key});

  final List<Gateway> gateways;
  final Map<String, StationGroupName> groupNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cuando la vista mezcla organizaciones (Admin de plataforma), cada una
    // encabeza sus estaciones fuera de las tarjetas (2026-09-18, elección del
    // usuario); dentro de la tarjeta queda la finca.
    final porOrganizacion = <String, List<Gateway>>{};
    for (final gateway in gateways) {
      final organizacion = groupNames[gateway.installationId]?.organization ?? '';
      (porOrganizacion[organizacion] ??= []).add(gateway);
    }
    final organizaciones = porOrganizacion.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final organizacion in organizaciones) ...[
          if (organizacion.isNotEmpty) _OrganizationHeader(name: organizacion),
          for (final gateway in porOrganizacion[organizacion]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StationSummaryCard(gateway: gateway, groupName: groupNames[gateway.installationId]),
            ),
        ],
      ],
    );
  }
}

/// Cabecera de las estaciones de una organización, fuera de las tarjetas.
class _OrganizationHeader extends StatelessWidget {
  const _OrganizationHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(name, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class StationSummaryCard extends ConsumerWidget {
  const StationSummaryCard({required this.gateway, required this.groupName, super.key});

  final Gateway gateway;
  final StationGroupName? groupName;

  /// Como mucho, cuatro cifras en el resumen: la principal de cada sensor y,
  /// si sobran huecos, las siguientes de cada uno. El resto, en la estación.
  static const maxTiles = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final soft = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final readings = ref.watch(gatewayLatestReadingsProvider(gateway.id));
    final (statusLabel, statusTone) = GatewayStatusLabels.forStatus(gateway.status);
    final lastSeen = gateway.lastSeenAt;
    // La organización va en la cabecera del grupo, fuera de la tarjeta.
    final place = [if (groupName?.farm != null) groupName!.farm];

    return AppCard(
      onTap: () => context.go('/stations/${gateway.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gateway.name, style: theme.textTheme.titleMedium),
                    for (final line in place) Text(line, style: soft),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(label: statusLabel, tone: statusTone),
                  if (lastSeen != null) ...[
                    const SizedBox(height: 4),
                    Text(formatAgo(lastSeen), style: soft),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          readings.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => RetryMessage(
              message: 'No se han podido cargar los datos de esta estación.',
              technicalDetail: '$error',
              onRetry: () => ref.invalidate(gatewayLatestReadingsProvider(gateway.id)),
            ),
            data: (items) {
              final dataState = stationDataState(gateway, items);
              final notice = dataState.state == StationDataState.ok
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: StationDataNotice(state: dataState.state, since: dataState.since),
                    );
              // El grupo de estado de la estación (batería, cobertura) no es un
              // sensor de campo: no sale en las cifras ni cuenta en el pie.
              final sensorGroups = [
                for (final g in groupReadingsBySensor(items))
                  if (!isStationHealthGroup(g)) g,
              ];
              if (sensorGroups.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (notice != null) notice,
                    Text('Aún no ha enviado datos de sensores.', style: theme.textTheme.bodyMedium),
                  ],
                );
              }
              final aliveAt = stationAliveAt(gateway, items);
              final sensorCount = sensorGroups.length;
              final magnitudeCount = sensorGroups.fold<int>(0, (sum, g) => sum + g.readings.length);
              final shown = summaryReadings(items, max: maxTiles);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null) notice,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 12.0;
                      final width = (constraints.maxWidth - gap) / 2;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 12,
                        children: [
                          for (final item in shown)
                            SizedBox(
                              width: width,
                              child: _SummaryTile(
                                gateway: gateway,
                                sensor: item.sensor,
                                reading: item.reading,
                                stale: isReadingStale(item.reading, aliveAt),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sensorCount == 1 ? '1 sensor, $magnitudeCount magnitudes' : '$sensorCount sensores, $magnitudeCount magnitudes',
                          style: soft,
                        ),
                      ),
                      Text('Ver gráficas', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                      Icon(Icons.chevron_right, color: theme.colorScheme.primary, size: 20),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends ConsumerWidget {
  const _SummaryTile({required this.gateway, required this.sensor, required this.reading, required this.stale});

  final Gateway gateway;
  final SensorReadings sensor;
  final LatestReading reading;

  /// El sensor ha dejado de contestar: su última cifra se queda atrás.
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final soft = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final organizationId = ref.watch(stationOrganizationIdProvider(gateway.id));
    final trend = ref.watch(stationSparklineProvider((organizationId, reading.channelId))).valueOrNull;
    final unit = ChannelTypeLabels.unitFor(reading.channelTypeCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ChannelTypeLabels.labelFor(reading.channelTypeCode), style: soft, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sensor.label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatReading(reading.value),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                    ),
                    TextSpan(text: ' $unit', style: soft),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (trend != null && trend.length >= 2) Sparkline(points: trend, width: 48, height: 22),
          ],
        ),
        if (stale) StaleReadingNote(since: reading.tsOrigin),
      ],
    );
  }
}

/// Tendencia en miniatura: la línea de las últimas 24 h con el último punto
/// marcado. Sin ejes: es para ver de un vistazo si sube, baja o está plana.
class Sparkline extends StatelessWidget {
  const Sparkline({required this.points, required this.width, required this.height, super.key});

  final List<HistoryPoint> points;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, height),
        painter: _SparklinePainter(
          values: [for (final p in points) p.value],
          line: theme.colorScheme.onSurfaceVariant,
          end: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.line, required this.end});

  final List<double> values;
  final Color line;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    const pad = 3.0;
    Offset at(int i) => Offset(
          pad + i * (size.width - 2 * pad) / (values.length - 1),
          size.height - pad - (values[i] - min) / span * (size.height - 2 * pad),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 2.5, Paint()..color = end);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.line != line || oldDelegate.end != end;
}
