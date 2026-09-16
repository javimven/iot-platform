import '../../readings/application/reading_history_controller.dart';
import '../../readings/data/reading_history_models.dart';

/// Una franja de tiempo con su acumulado — 6h (1 día/2 días) o 1 día
/// (semana/mes/2 meses). `start` es hora local (1/2 días) o UTC
/// (semana+) — solo se usa para la etiqueta del eje/tooltip.
class AccumulatedSlot {
  const AccumulatedSlot({required this.start, required this.value});
  final DateTime start;
  final double value;
}

/// Construye las franjas fijas de [AccumulatedChart] a partir del histórico
/// en crudo de un canal "de acumulados" (lluvia) — BACKLOG.md #30.
///
/// - **1 día / 2 días**: franjas fijas de 6h en **hora local** (0-6, 6-12,
///   12-18, 18-24) para hoy (1 día) o ayer+hoy (2 días). Solo se incluyen
///   las franjas ya completadas — nunca una franja futura.
/// - **semana / 1 mes / 2 meses**: una franja por día (UTC, igual criterio
///   que `date_trunc('day', ts_origin)` del backend) sobre el rango
///   completo solicitado — un día sin lecturas se incluye igual, con
///   acumulado 0, para no comprimir el eje a solo los días con dato.
///
/// `now` es inyectable (por defecto `DateTime.now()`) solo para que los
/// tests puedan fijar un instante exacto — el filtro de "franja ya
/// completada" depende de la hora actual, no es una función pura sin él.
List<AccumulatedSlot> buildAccumulatedSlots(List<HistoryPoint> points, HistoryRange range, {DateTime? now}) {
  final isShortRange = range == HistoryRange.day || range == HistoryRange.twoDays;

  if (isShortRange) {
    final effectiveNow = now ?? DateTime.now();
    final days = range == HistoryRange.day ? 1 : 2;
    final todayStart = DateTime(effectiveNow.year, effectiveNow.month, effectiveNow.day);
    final firstDayStart = todayStart.subtract(Duration(days: days - 1));

    final sums = <DateTime, double>{
      for (var d = firstDayStart; !d.isAfter(todayStart); d = d.add(const Duration(days: 1)))
        for (final hour in [0, 6, 12, 18]) DateTime(d.year, d.month, d.day, hour): 0.0,
    };
    for (final p in points) {
      final local = p.tsOrigin.toLocal();
      if (local.isBefore(firstDayStart)) continue;
      final bucketHour = (local.hour ~/ 6) * 6;
      final bucketStart = DateTime(local.year, local.month, local.day, bucketHour);
      if (!sums.containsKey(bucketStart)) continue;
      sums[bucketStart] = sums[bucketStart]! + p.value;
    }

    final starts = sums.keys.toList()..sort();
    return [
      for (final start in starts)
        if (!start.add(const Duration(hours: 6)).isAfter(effectiveNow))
          AccumulatedSlot(start: start, value: sums[start]!),
    ];
  }

  final effectiveNowUtc = (now ?? DateTime.now()).toUtc();
  final from = effectiveNowUtc.subtract(range.span);
  final fromDay = DateTime.utc(from.year, from.month, from.day);
  final toDay = DateTime.utc(effectiveNowUtc.year, effectiveNowUtc.month, effectiveNowUtc.day);
  final byDay = <DateTime, double>{
    for (final p in points) DateTime.utc(p.tsOrigin.year, p.tsOrigin.month, p.tsOrigin.day): p.value,
  };
  return [
    for (var d = fromDay; !d.isAfter(toDay); d = d.add(const Duration(days: 1)))
      AccumulatedSlot(start: d, value: byDay[d] ?? 0),
  ];
}
