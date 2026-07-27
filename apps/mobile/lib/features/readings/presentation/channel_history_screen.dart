import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/channel_type_labels.dart';
import '../application/reading_history_controller.dart';
import '../data/reading_history_models.dart';

/// Gráfica histórica de un canal (FUNCTIONAL_REQUIREMENTS.md §12): 24h en
/// crudo, 7 días u 30 días agregados (media con banda mín/máx cuando el
/// backend la devuelve, ReadingsService).
class ChannelHistoryScreen extends ConsumerWidget {
  final String channelId;
  final String channelTypeCode;

  const ChannelHistoryScreen({
    super.key,
    required this.channelId,
    required this.channelTypeCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(channelHistoryProvider(channelId));
    final range = ref.watch(historyRangeProvider);
    final label = ChannelTypeLabels.labelFor(channelTypeCode);
    final unit = ChannelTypeLabels.unitFor(channelTypeCode);

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<HistoryRange>(
              segments: HistoryRange.values
                  .map((r) => ButtonSegment(value: r, label: Text(r.label)))
                  .toList(),
              selected: {range},
              onSelectionChanged: (selection) =>
                  ref.read(historyRangeProvider.notifier).state = selection.first,
            ),
          ),
          Expanded(
            child: history.when(
              data: (points) {
                if (points.isEmpty) {
                  return const Center(child: Text('No hay datos para este rango.'));
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 24, 24),
                  child: _HistoryChart(points: points, unit: unit, range: range),
                );
              },
              error: (error, _) =>
                  Center(child: Text('No se pudo cargar el histórico.\n$error')),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  final List<HistoryPoint> points;
  final String unit;
  final HistoryRange range;

  const _HistoryChart({required this.points, required this.unit, required this.range});

  double _x(DateTime t) => t.millisecondsSinceEpoch.toDouble();

  bool get _hasMinMax => points.any((p) => p.min != null && p.max != null);

  String _timeLabel(double millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(millis.toInt());
    return range == HistoryRange.day ? DateFormat('HH:mm').format(t) : DateFormat('dd/MM').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final minX = _x(points.first.tsOrigin);
    final maxX = _x(points.last.tsOrigin);
    final xSpan = (maxX - minX).clamp(1, double.infinity);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(0)} $unit'),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: xSpan / 4,
              getTitlesWidget: (value, meta) => Text(_timeLabel(value)),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem('${s.y.toStringAsFixed(1)} $unit', const TextStyle()))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points.map((p) => FlSpot(_x(p.tsOrigin), p.value)).toList(),
            isCurved: false,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
          if (_hasMinMax) ...[
            LineChartBarData(
              spots: points
                  .where((p) => p.min != null)
                  .map((p) => FlSpot(_x(p.tsOrigin), p.min!))
                  .toList(),
              isCurved: false,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              barWidth: 1,
              dashArray: const [4, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            LineChartBarData(
              spots: points
                  .where((p) => p.max != null)
                  .map((p) => FlSpot(_x(p.tsOrigin), p.max!))
                  .toList(),
              isCurved: false,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              barWidth: 1,
              dashArray: const [4, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ],
      ),
    );
  }
}
