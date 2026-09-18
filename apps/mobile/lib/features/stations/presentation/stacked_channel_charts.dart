import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/format/reading_format.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import '../application/station_detail_controller.dart';
import 'chart_axis.dart';
import 'series_style.dart';

/// Una magnitud a dibujar en [StackedChannelCharts], con sus puntos ya
/// cargados para el rango activo.
class StackedSeries {
  const StackedSeries({
    required this.channelId,
    required this.label,
    required this.unit,
    required this.points,
    required this.color,
    required this.dash,
  });

  final String channelId;
  final String label;
  final String unit;
  final List<HistoryPoint> points;
  final Color color;
  final List<int>? dash;
}

/// Una gráfica por magnitud, apiladas y con el mismo eje de tiempo (BACKLOG.md
/// #49, mejora D). Cada una lleva su propio eje Y con su unidad, en vez de
/// mezclar magnitudes en un eje oculto y reescalado. Tocar o arrastrar sobre
/// cualquiera marca esa hora en todas con una línea vertical, y encima se lee
/// el valor de cada magnitud en ese instante.
class StackedChannelCharts extends StatelessWidget {
  const StackedChannelCharts({
    required this.series,
    required this.range,
    required this.crosshairMillis,
    required this.onCrosshair,
    this.chartHeight,
    this.showReadout = true,
    super.key,
  });

  final List<StackedSeries> series;
  final HistoryRange range;
  final double? crosshairMillis;
  final ValueChanged<double> onCrosshair;

  /// Alto de cada gráfica; por defecto, más alto cuantas menos haya.
  final double? chartHeight;

  /// La lectura del instante marcado, encima. En la pantalla de una estación
  /// va aparte, fija arriba mientras se baja por la página (2026-09-18).
  final bool showReadout;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    final to = DateTime.now();
    final from = to.subtract(range.span);
    final height = chartHeight ?? switch (series.length) { 1 => 240.0, 2 => 180.0, _ => 150.0 };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReadout) ...[
          ChannelReadout(series: series, crosshairMillis: crosshairMillis, range: range),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < series.length; i++) ...[
          _ChartHeader(series: series[i], crosshairMillis: crosshairMillis),
          SizedBox(
            height: height,
            child: _SingleChannelChart(
              series: series[i],
              minX: from.millisecondsSinceEpoch.toDouble(),
              maxX: to.millisecondsSinceEpoch.toDouble(),
              showTimeAxis: i == series.length - 1,
              crosshairMillis: crosshairMillis,
              onCrosshair: onCrosshair,
            ),
          ),
          if (i < series.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Lectura del instante marcado: hora y valor de cada magnitud, cada uno en su
/// color. Sin marca, una pista de cómo obtenerla.
class ChannelReadout extends StatelessWidget {
  const ChannelReadout({
    required this.series,
    required this.crosshairMillis,
    required this.range,
    this.maxLines,
    super.key,
  });

  final List<StackedSeries> series;
  final double? crosshairMillis;
  final HistoryRange range;

  /// Recortar a este número de líneas (la barra fija de la estación).
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soft = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final millis = crosshairMillis;
    if (millis == null) {
      return Text(
        'Toca o arrastra sobre la gráfica para leer los valores.',
        style: soft,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }

    final instant = DateTime.fromMillisecondsSinceEpoch(millis.round());
    final now = DateTime.now();
    final isToday = instant.year == now.year && instant.month == now.month && instant.day == now.day;
    final daily = range == HistoryRange.month || range == HistoryRange.twoMonths;
    final when = daily
        ? DateFormat('dd/MM').format(instant)
        : isToday
            ? 'Hoy, ${DateFormat('HH:mm').format(instant)}'
            : DateFormat('dd/MM HH:mm').format(instant);

    return Text.rich(
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabularFigures),
        children: [
          TextSpan(text: when, style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final s in series)
            if (nearestPoint(s.points, millis) case final point?)
              TextSpan(
                text: '   ${s.label} ${formatReading(point.value)} ${s.unit}',
                style: TextStyle(color: s.color, fontWeight: FontWeight.w600),
              ),
        ],
      ),
    );
  }
}

/// Cabecera de una gráfica: su magnitud y, con el dedo puesto, su valor en ese
/// instante, para que se lea también con la barra de arriba lejos o recortada.
class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.series, required this.crosshairMillis});

  final StackedSeries series;
  final double? crosshairMillis;

  @override
  Widget build(BuildContext context) {
    final millis = crosshairMillis;
    final marked = millis == null ? null : nearestPoint(series.points, millis);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SeriesSwatch(color: series.color, dash: series.dash),
          const SizedBox(width: 8),
          Text('${series.label} (${series.unit})', style: Theme.of(context).textTheme.labelMedium),
          if (marked != null) ...[
            const SizedBox(width: 8),
            Text(
              formatReading(marked.value),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: series.color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
            ),
          ],
        ],
      ),
    );
  }
}

class _SingleChannelChart extends StatelessWidget {
  const _SingleChannelChart({
    required this.series,
    required this.minX,
    required this.maxX,
    required this.showTimeAxis,
    required this.crosshairMillis,
    required this.onCrosshair,
  });

  final StackedSeries series;
  final double minX;
  final double maxX;
  final bool showTimeAxis;
  final double? crosshairMillis;
  final ValueChanged<double> onCrosshair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = series.points;
    if (points.isEmpty) {
      return Center(child: Text('No hay datos en este rango.', style: theme.textTheme.bodyMedium));
    }

    final values = points.map((p) => p.value);
    final niceY = computeNiceYAxis(
      values.reduce((a, b) => a < b ? a : b),
      values.reduce((a, b) => a > b ? a : b),
      targetTicks: 4,
    );
    final spots = [for (final p in points) FlSpot(p.tsOrigin.millisecondsSinceEpoch.toDouble(), p.value)];
    final marked = crosshairMillis == null ? null : nearestPoint(points, crosshairMillis!);
    final markedX = marked?.tsOrigin.millisecondsSinceEpoch.toDouble();
    final gridColor = theme.colorScheme.outline;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: tabularFigures,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final timeAxis = computeTimeAxisConfig(
          start: DateTime.fromMillisecondsSinceEpoch(minX.round()),
          end: DateTime.fromMillisecondsSinceEpoch(maxX.round()),
          availableWidthPx: constraints.maxWidth,
        );

        return LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: niceY.min,
            maxY: niceY.max,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: niceY.step,
              getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: niceY.step,
                  getTitlesWidget: (value, meta) {
                    // fl_chart añade marcas en los extremos que no caen en el paso.
                    final steps = (value - niceY.min) / niceY.step;
                    if ((steps - steps.roundToDouble()).abs() > 0.01) return const SizedBox.shrink();
                    return Text(niceY.format(value), style: axisStyle);
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: showTimeAxis,
                  reservedSize: 24,
                  interval: timeAxis.intervalMs,
                  getTitlesWidget: (value, meta) {
                    final tolerance = timeAxis.intervalMs * 0.02;
                    if (value <= minX + tolerance || value >= maxX - tolerance) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(timeAxis.formatTick(value), style: axisStyle),
                    );
                  },
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              verticalLines: [
                if (markedX != null)
                  VerticalLine(
                    x: markedX,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    strokeWidth: 1,
                    dashArray: const [3, 3],
                  ),
              ],
            ),
            lineTouchData: LineTouchData(
              handleBuiltInTouches: false,
              // Siempre el punto más cercano en horizontal, esté donde esté el dedo.
              touchSpotThreshold: double.infinity,
              touchCallback: (event, response) {
                final isTouchMove = event is FlTapDownEvent ||
                    event is FlPanStartEvent ||
                    event is FlPanUpdateEvent ||
                    event is FlLongPressStart ||
                    event is FlLongPressMoveUpdate ||
                    event is FlPointerHoverEvent;
                final spot = response?.lineBarSpots?.firstOrNull;
                if (isTouchMove && spot != null) onCrosshair(spot.x);
              },
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: series.color,
                barWidth: 2.5,
                dashArray: series.dash,
                isCurved: false,
                dotData: FlDotData(
                  show: markedX != null,
                  checkToShowDot: (spot, _) => spot.x == markedX,
                  getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                    radius: 4,
                    color: theme.colorScheme.surface,
                    strokeColor: series.color,
                    strokeWidth: 2,
                  ),
                ),
                belowBarData: BarAreaData(show: true, color: series.color.withValues(alpha: 0.08)),
              ),
            ],
          ),
          duration: Duration.zero,
        );
      },
    );
  }
}
