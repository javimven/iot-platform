import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../data/satellite_models.dart';

/// Evolución del NDVI de una parcela.
///
/// Reutiliza `fl_chart`, la misma librería que las gráficas de telemetría, y
/// el mismo eje temporal — el backend devuelve `tsOrigin`/`value` a propósito
/// para que esto no tenga que traducir nada.
///
/// Dos diferencias respecto a una gráfica de sensor, y las dos importan:
///
/// 1. **Los puntos son escasos e irregulares.** Sentinel-2 pasa cada ~5 días y
///    los días nublados se descartan, así que puede haber tres semanas sin
///    nada. Se pintan los puntos, no solo la línea: una línea sola daría a
///    entender que hay medidas continuas.
/// 2. **La calidad se ve.** Una observación medio tapada se dibuja hueca, para
///    que no pese lo mismo a simple vista que una limpia.
class NdviChart extends StatelessWidget {
  const NdviChart({required this.puntos, super.key});

  final List<PuntoSatelite> puntos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordenados = [...puntos]..sort((a, b) => a.tsOrigin.compareTo(b.tsOrigin));

    final spots = [
      for (final punto in ordenados)
        FlSpot(punto.tsOrigin.millisecondsSinceEpoch.toDouble(), punto.value),
    ];

    final primera = ordenados.first.tsOrigin;
    final ultima = ordenados.last.tsOrigin;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          // El NDVI llega a 1 en teoría, pero un cultivo real rara vez pasa de
          // 0,9: fijar el techo ahí aprovecha el alto de la gráfica.
          maxY: 0.9,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false, // no se inventan valores entre pasada y pasada
              color: AppColors.brand,
              barWidth: 2,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, indice) {
                  final punto = ordenados[indice];
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: punto.esFiable ? AppColors.brand : theme.colorScheme.surface,
                    strokeWidth: 2,
                    strokeColor: AppColors.brand,
                  );
                },
              ),
            ),
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: 0.3,
                getTitlesWidget: (valor, meta) => Text(
                  valor.toStringAsFixed(1),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                // Solo los extremos: con pasadas irregulares, una rejilla de
                // fechas uniformes engaña más de lo que ayuda.
                interval: (ultima.millisecondsSinceEpoch - primera.millisecondsSinceEpoch)
                        .toDouble()
                        .clamp(1, double.infinity) /
                    2,
                getTitlesWidget: (valor, meta) => Text(
                  DateFormat('dd/MM').format(
                    DateTime.fromMillisecondsSinceEpoch(valor.toInt()),
                  ),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.3),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}\n'
                    'NDVI ${spot.y.toStringAsFixed(2)}',
                    theme.textTheme.bodySmall ?? const TextStyle(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
