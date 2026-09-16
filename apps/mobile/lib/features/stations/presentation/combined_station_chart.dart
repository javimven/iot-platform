import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import 'chart_axis.dart';

/// Una serie de línea a dibujar en [CombinedStationChart] — un canal de
/// agregación `average` (temperatura, humedad...) de una estación, con los
/// puntos ya cargados para el rango activo de esa tarjeta. Los canales de
/// agregación `sum` (lluvia) nunca llegan aquí — tienen su propia gráfica,
/// [AccumulatedChart], sin combinar con las de línea (pedido explícito:
/// visualmente no tiene sentido mezclar una magnitud continua con una
/// acumulada por franjas).
class ChannelSeries {
  final String channelId;
  final String label;
  final String unit;
  final List<HistoryPoint> points;
  final Color color;

  const ChannelSeries({
    required this.channelId,
    required this.label,
    required this.unit,
    required this.points,
    required this.color,
  });
}

/// Gráfica de línea de la tarjeta de una Estación (BACKLOG.md #30) — combina
/// varios canales `average` a la vez. El eje X es tiempo real continuo
/// (milisegundos desde época), con `minX`/`maxX` fijados al rango
/// **solicitado** (`HistoryRange.span` desde ahora), no al rango de los
/// datos existentes — así una estación con pocos datos en un rango de 1/2
/// meses muestra ese hueco vacío tal cual, en vez de estirar los pocos
/// puntos reales para que parezca que ocupan todo el ancho.
///
/// Con 2 o más canales a la vez, el eje Y no muestra ningún valor: si no
/// comparten unidad, cualquier número sería solo de una de las magnitudes o
/// de una escala normalizada sin significado directo. El dato real de cada
/// canal, con su unidad, se lee en la píldora, la leyenda y el tooltip
/// (nunca solo color).
class CombinedStationChart extends StatelessWidget {
  const CombinedStationChart({required this.series, required this.range, super.key});

  final List<ChannelSeries> series;
  final HistoryRange range;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const SizedBox.shrink();
    }

    final units = series.map((s) => s.unit).toSet();
    final normalizeForDisplay = units.length > 1;
    final showAxisValues = series.length == 1;
    final hasAnyData = series.any((s) => s.points.isNotEmpty);

    final to = DateTime.now().toUtc();
    final from = to.subtract(range.span);
    final minX = from.millisecondsSinceEpoch.toDouble();
    final maxX = to.millisecondsSinceEpoch.toDouble();

    // Valor real (tooltip, siempre) indexado por milisegundo exacto, y valor
    // a pintar (normalizado a [0,1] solo si hace falta compartir un eje
    // entre unidades distintas — "indexar a una base común", nunca dos ejes
    // con escalas distintas).
    final rawByChannelMillis = <String, Map<int, double>>{};
    final plottedSpots = <String, List<FlSpot>>{};
    for (final s in series) {
      if (s.points.isEmpty) {
        plottedSpots[s.channelId] = const [];
        continue;
      }
      final values = s.points.map((p) => p.value);
      final min = values.reduce((a, b) => a < b ? a : b);
      final max = values.reduce((a, b) => a > b ? a : b);
      final span = (max - min).abs() < 1e-9 ? 1.0 : (max - min);
      rawByChannelMillis[s.channelId] = {
        for (final p in s.points) p.tsOrigin.millisecondsSinceEpoch: p.value,
      };
      plottedSpots[s.channelId] = [
        for (final p in s.points)
          FlSpot(
            p.tsOrigin.millisecondsSinceEpoch.toDouble(),
            normalizeForDisplay ? (p.value - min) / span : p.value,
          ),
      ];
    }

    double minY;
    double maxY;
    if (normalizeForDisplay) {
      minY = 0;
      maxY = 1;
    } else if (hasAnyData) {
      final allValues = series.expand((s) => s.points.map((p) => p.value));
      minY = allValues.reduce((a, b) => a < b ? a : b);
      maxY = allValues.reduce((a, b) => a > b ? a : b);
      if ((maxY - minY).abs() < 1e-9) {
        maxY += 1; // evita un eje degenerado si todos los valores son iguales
      }
    } else {
      minY = 0;
      maxY = 1;
    }

    // Límites e intervalo "bonitos" del eje Y (5-7 divisiones, sin
    // decimales largos) — solo se usan como límites reales del gráfico
    // cuando se muestran valores (1 canal); con varios canales el eje va
    // oculto y se mantiene el rango normalizado [0,1] tal cual.
    final niceY = computeNiceYAxis(minY, maxY);
    final plotMinY = showAxisValues ? niceY.min : minY;
    final plotMaxY = showAxisValues ? niceY.max : maxY;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final timeAxis = computeTimeAxisConfig(
                start: DateTime.fromMillisecondsSinceEpoch(minX.round()),
                end: DateTime.fromMillisecondsSinceEpoch(maxX.round()),
                availableWidthPx: constraints.maxWidth,
              );

              return Stack(
                alignment: Alignment.center,
                children: [
                  LineChart(
                    LineChartData(
                      minX: minX,
                      maxX: maxX,
                      minY: plotMinY,
                      maxY: plotMaxY,
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: true),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: showAxisValues,
                            reservedSize: 40,
                            interval: niceY.step,
                            getTitlesWidget: (value, meta) => Text(niceY.format(value)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: timeAxis.intervalMs,
                            getTitlesWidget: (value, meta) {
                              // `fl_chart` siempre fuerza una marca extra
                              // exactamente en minX/maxX además de las
                              // espaciadas por `interval` — si esa marca
                              // forzada no cae en la propia rejilla (caso
                              // normal, ya que minX/maxX son "ahora menos
                              // el rango", no una hora en punto), se oculta
                              // para no solapar con la marca de rejilla más
                              // cercana.
                              final stepsFromStart = (value - minX) / timeAxis.intervalMs;
                              final isOnGrid = (stepsFromStart - stepsFromStart.roundToDouble()).abs() < 0.05;
                              if (!isOnGrid) return const SizedBox.shrink();
                              // Cuando SÍ cae en la rejilla siendo además el
                              // propio extremo (minX/maxX), esa marca forzada
                              // coincide en valor con la marca "normal" de la
                              // rejilla en ese mismo punto — `fl_chart` las
                              // pinta como dos widgets superpuestos con un
                              // pequeño desfase, dando el efecto de texto
                              // duplicado/fantasma. Se oculta ese extremo por
                              // completo (igual que ya se hace en la gráfica
                              // de barras) y se dejan solo las marcas
                              // interiores, que no tienen este problema.
                              final tolerance = timeAxis.intervalMs * 0.02;
                              final isAtEdge = value <= minX + tolerance || value >= maxX - tolerance;
                              if (isAtEdge) return const SizedBox.shrink();
                              return Text(timeAxis.formatTick(value));
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (spots) {
                            if (spots.isEmpty) return [];
                            final header = DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(spots.first.x.round()));
                            return spots.asMap().entries.map((entry) {
                              final spot = entry.value;
                              final s = series[spot.barIndex];
                              final real = rawByChannelMillis[s.channelId]?[spot.x.round()];
                              final reading = real == null ? s.label : '${s.label}: ${real.toStringAsFixed(1)} ${s.unit}';
                              final readingStyle = TextStyle(color: s.color, fontWeight: FontWeight.w600);
                              if (entry.key != 0) return LineTooltipItem(reading, readingStyle);
                              return LineTooltipItem(
                                '$header\n',
                                const TextStyle(color: AppColors.sidebarInkSoft, fontWeight: FontWeight.normal),
                                children: [TextSpan(text: reading, style: readingStyle)],
                              );
                            }).toList();
                          },
                        ),
                      ),
                      lineBarsData: [
                        for (final s in series)
                          LineChartBarData(
                            spots: plottedSpots[s.channelId]!,
                            isCurved: false,
                            color: s.color,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: false),
                          ),
                      ],
                    ),
                  ),
                  if (!hasAnyData)
                    Text('No hay datos para este rango.', style: Theme.of(context).textTheme.bodyMedium),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: series.map((s) => _LegendChip(color: s.color, label: '${s.label} (${s.unit})')).toList(),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
