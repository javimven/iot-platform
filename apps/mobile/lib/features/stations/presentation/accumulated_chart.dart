import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/accumulated_slots.dart';
import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';
import 'chart_axis.dart';
import 'chart_axis_format.dart';

/// Gráfica "de acumulados" (lluvia, `channel_types.default_aggregation =
/// sum`) — separada por completo de [CombinedStationChart] (BACKLOG.md #30:
/// no tiene sentido visual combinar una magnitud continua con una
/// acumulada por franjas fijas). Las franjas se calculan en
/// `application/accumulated_slots.dart` (función pura, con tests propios).
///
/// - **1 día / 2 días**: franjas fijas de 6h en **hora local** — 0-6, 6-12,
///   12-18, 18-24 — para el día de hoy (1 día) o ayer+hoy (2 días). Solo se
///   muestran las franjas ya completadas — nunca una franja futura vacía.
///   Cada franja se dibuja como un rectángulo que ocupa **todo** el ancho de
///   esa franja horaria, con la altura del acumulado — sin marcas de
///   lecturas puntuales dentro (se probaron y se quitaron: no aportaban
///   nada frente al acumulado). Se construye a mano (no con `fl_chart`'s
///   `BarChart`, pensado para barras agrupadas lado a lado con separación,
///   no para rectángulos pegados de borde a borde) para que 00:00 quede en
///   el extremo izquierdo y la medianoche siguiente en el extremo derecho.
/// - **semana / 1 mes / 2 meses**: acumulado por día con `fl_chart`, sobre
///   el rango completo solicitado — un hueco real (sin datos) se deja en
///   blanco, no se comprime el eje a solo los días con dato.
class AccumulatedChart extends StatelessWidget {
  const AccumulatedChart({
    required this.label,
    required this.unit,
    required this.color,
    required this.rawPoints,
    required this.range,
    super.key,
  });

  final String label;
  final String unit;
  final Color color;
  final List<HistoryPoint> rawPoints;
  final HistoryRange range;

  bool get _isShortRange => range == HistoryRange.day || range == HistoryRange.twoDays;

  @override
  Widget build(BuildContext context) {
    final slots = buildAccumulatedSlots(rawPoints, range);
    if (slots.isEmpty) {
      return Center(
        child: Text(
          'Todavía no ha pasado ninguna franja completa en este rango.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final hasAnyData = slots.any((s) => s.value > 0);
    final maxValue = slots.map((s) => s.value).reduce((a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    return Column(
      children: [
        Expanded(
          child: _isShortRange
              ? _ShortRangeSlots(slots: slots, maxY: maxY, color: color, unit: unit, hasAnyData: hasAnyData)
              : _LongRangeBarChart(slots: slots, maxY: maxY, color: color, unit: unit, hasAnyData: hasAnyData),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, color: color),
            const SizedBox(width: 4),
            Text('$label ($unit)', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

/// 1 día / 2 días: rectángulos de ancho completo por franja, con las
/// lecturas puntuales dentro, fijadas a su posición horaria real.
class _ShortRangeSlots extends StatelessWidget {
  const _ShortRangeSlots({
    required this.slots,
    required this.maxY,
    required this.color,
    required this.unit,
    required this.hasAnyData,
  });

  final List<AccumulatedSlot> slots;
  final double maxY;
  final Color color;
  final String unit;
  final bool hasAnyData;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatAxisValue(maxY), style: Theme.of(context).textTheme.labelSmall),
                        Text('0', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final slot in slots)
                          Expanded(child: _SlotBox(slot: slot, maxY: maxY, color: color, unit: unit)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Row(
                    children: [
                      for (final slot in slots)
                        Expanded(
                          child: Center(
                            child: Text('${slot.start.hour}h', style: Theme.of(context).textTheme.labelSmall),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (!hasAnyData)
          Text('Sin lluvia registrada en este rango.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Una franja: rectángulo (borde) cuya altura representa el acumulado de
/// esa franja — sin marcas individuales dentro (se probó con una barrita
/// por lectura puntual, pero resultó innecesario: solo el acumulado
/// aporta valor aquí).
class _SlotBox extends StatelessWidget {
  const _SlotBox({required this.slot, required this.maxY, required this.color, required this.unit});

  final AccumulatedSlot slot;
  final double maxY;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxHeight = maxY <= 0 ? 0.0 : (slot.value / maxY).clamp(0.0, 1.0) * constraints.maxHeight;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: '${slot.start.hour}h-${slot.start.add(const Duration(hours: 6)).hour}h: '
                '${slot.value.toStringAsFixed(1)} $unit acumulados',
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: boxHeight,
                width: double.infinity,
                child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: color, width: 2))),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Semana / 1 mes / 2 meses: una barra por día con `fl_chart` — sin cambios
/// respecto a la versión anterior, ya confirmada como correcta.
class _LongRangeBarChart extends StatelessWidget {
  const _LongRangeBarChart({
    required this.slots,
    required this.maxY,
    required this.color,
    required this.unit,
    required this.hasAnyData,
  });

  final List<AccumulatedSlot> slots;
  final double maxY;
  final Color color;
  final String unit;
  final bool hasAnyData;

  @override
  Widget build(BuildContext context) {
    // Límites e intervalo "bonitos" del eje Y (5-7 divisiones) — el mínimo
    // real siempre es 0 (un acumulado no puede ser negativo).
    final niceY = computeNiceYAxis(0, maxY);
    final dateFormat = timeLabelFormatterFor(Duration(days: slots.length));

    return LayoutBuilder(
      builder: (context, constraints) {
        final indexStep = pickIndexStep(slots.length, constraints.maxWidth);

        return Stack(
          alignment: Alignment.center,
          children: [
            BarChart(
              BarChartData(
                maxY: niceY.max,
                alignment: BarChartAlignment.spaceBetween,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: true),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final s = slots[group.x];
                      return BarTooltipItem(
                        '${DateFormat('dd/MM/yyyy').format(s.start)}\n${s.value.toStringAsFixed(1)} $unit',
                        TextStyle(color: color, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: niceY.step,
                      getTitlesWidget: (value, meta) => Text(niceY.format(value)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        // Con `BarChartAlignment.spaceBetween`, la barra 0 y
                        // la última quedan centradas justo en los bordes del
                        // recuadro — su etiqueta, centrada en ese punto, se
                        // solaparía con la columna del eje Y (izquierda) o se
                        // saldría del recuadro (derecha). Se ocultan y solo
                        // se muestran fechas interiores, con margen de sobra.
                        if (index <= 0 || index >= slots.length - 1) return const SizedBox.shrink();
                        if (index % indexStep != 0) return const SizedBox.shrink();
                        return Text(dateFormat(slots[index].start));
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < slots.length; i++)
                    BarChartGroupData(x: i, barRods: [BarChartRodData(toY: slots[i].value, color: color, width: 14)]),
                ],
              ),
            ),
            if (!hasAnyData)
              Text('Sin lluvia registrada en este rango.', style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
