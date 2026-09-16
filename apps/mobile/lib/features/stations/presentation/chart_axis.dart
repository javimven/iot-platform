import 'dart:math' as math;

import '../../../core/format/reading_format.dart';

/// Lógica de ejes compartida por todas las gráficas de Estaciones
/// (`CombinedStationChart`, `AccumulatedChart`) — pensada para no
/// duplicarse por gráfica: cálculo de intervalos "bonitos" del eje Y
/// ([computeNiceYAxis]) y de marcas de tiempo del eje X adaptadas al
/// ancho real disponible ([computeTimeAxisConfig]), más el equivalente
/// para ejes de índice (una barra = un día, [pickIndexStep]).
///
/// Todas las funciones son puras y de coste O(1) (no recorren los puntos
/// de datos) — se pueden llamar en cada `build()` sin preocuparse por el
/// rendimiento, incluso con miles de mediciones en la serie.

// ---------------------------------------------------------------------------
// Eje Y — "nice numbers" (Heckbert): límites e intervalo redondos
// (1/2/5/10 × 10^n) en vez de decimales largos tipo 11.37/15.82/20.27.
// ---------------------------------------------------------------------------

class NiceYAxis {
  const NiceYAxis({required this.min, required this.max, required this.step, required this.decimals});

  final double min;
  final double max;
  final double step;
  final int decimals;

  String format(double value) => formatReading(value, decimals: decimals);
}

double _niceNum(double range, {required bool round}) {
  if (range <= 0) return 1;
  final exponent = (math.log(range) / math.ln10).floor();
  final fraction = range / math.pow(10, exponent);
  double niceFraction;
  if (round) {
    if (fraction < 1.5) {
      niceFraction = 1;
    } else if (fraction < 3) {
      niceFraction = 2;
    } else if (fraction < 7) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  } else {
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  }
  return niceFraction * math.pow(10, exponent).toDouble();
}

int _decimalsForStep(double step) {
  if (step <= 0) return 0;
  for (var d = 0; d <= 2; d++) {
    final scaled = step * math.pow(10, d);
    if ((scaled - scaled.roundToDouble()).abs() < 1e-6) return d;
  }
  return 2;
}

/// Calcula límites y paso "bonitos" para el eje Y a partir del rango real
/// de datos [dataMin, dataMax], apuntando a [targetTicks] divisiones (la
/// app usa 5-7, por defecto 6). Los límites devueltos siempre contienen
/// [dataMin, dataMax] — pueden ser algo más amplios para caer en un
/// número redondo.
NiceYAxis computeNiceYAxis(double dataMin, double dataMax, {int targetTicks = 6}) {
  var effectiveMax = dataMax;
  if ((effectiveMax - dataMin).abs() < 1e-9) {
    effectiveMax = dataMin + 1;
  }
  final range = _niceNum(effectiveMax - dataMin, round: false);
  final step = _niceNum(range / (targetTicks - 1), round: true);
  final niceMin = (dataMin / step).floor() * step;
  final niceMax = (effectiveMax / step).ceil() * step;
  return NiceYAxis(min: niceMin, max: niceMax, step: step, decimals: _decimalsForStep(step));
}

// ---------------------------------------------------------------------------
// Eje X (tiempo continuo) — nº de marcas según ancho disponible, paso
// redondo (minutos/horas/días/meses) y formato de fecha según el rango
// total visible.
// ---------------------------------------------------------------------------

const monthAbbrEs = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

enum _TimeStepUnit { minute, hour, day, month, year }

class _TimeStep {
  const _TimeStep(this.unit, this.amount);
  final _TimeStepUnit unit;
  final int amount;

  static const _msPerMinute = 60 * 1000;
  static const _msPerHour = 60 * _msPerMinute;
  static const _msPerDay = 24 * _msPerHour;
  static const _msPerMonth = 30 * _msPerDay;
  static const _msPerYear = 365 * _msPerDay;

  double get approxMs {
    switch (unit) {
      case _TimeStepUnit.minute:
        return (amount * _msPerMinute).toDouble();
      case _TimeStepUnit.hour:
        return (amount * _msPerHour).toDouble();
      case _TimeStepUnit.day:
        return (amount * _msPerDay).toDouble();
      case _TimeStepUnit.month:
        return (amount * _msPerMonth).toDouble();
      case _TimeStepUnit.year:
        return (amount * _msPerYear).toDouble();
    }
  }
}

const _minuteSteps = [1, 2, 5, 10, 15, 30, 60];
const _hourSteps = [1, 2, 3, 4, 6, 12];
const _daySteps = [1, 2, 3, 5, 7, 10, 14, 21, 30];
const _monthSteps = [1, 2, 3, 6];

_TimeStep _pickTimeStep(double idealStepMs) {
  final ladder = [
    for (final m in _minuteSteps) _TimeStep(_TimeStepUnit.minute, m),
    for (final h in _hourSteps) _TimeStep(_TimeStepUnit.hour, h),
    for (final d in _daySteps) _TimeStep(_TimeStepUnit.day, d),
    for (final mo in _monthSteps) _TimeStep(_TimeStepUnit.month, mo),
  ];
  for (final step in ladder) {
    if (step.approxMs >= idealStepMs) return step;
  }
  final years = idealStepMs / _TimeStep._msPerYear;
  final niceYears = _niceNum(years, round: true).round().clamp(1, 1000000);
  return _TimeStep(_TimeStepUnit.year, niceYears);
}

DateTime _floorTo(DateTime t, _TimeStep step) {
  switch (step.unit) {
    case _TimeStepUnit.minute:
      return DateTime(t.year, t.month, t.day, t.hour, t.minute - (t.minute % step.amount));
    case _TimeStepUnit.hour:
      return DateTime(t.year, t.month, t.day, t.hour - (t.hour % step.amount));
    case _TimeStepUnit.day:
      return DateTime(t.year, t.month, t.day);
    case _TimeStepUnit.month:
      return DateTime(t.year, t.month);
    case _TimeStepUnit.year:
      return DateTime(t.year);
  }
}

/// Formato de fecha adaptado al rango total visible — evita repetir
/// información innecesaria (año en un rango de horas, hora en un rango de
/// meses...). Horas: `14:00`. Días/semanas: `10 ago`. Meses: `ago`. Años:
/// `2026`.
String Function(DateTime) timeLabelFormatterFor(Duration totalSpan) {
  if (totalSpan <= const Duration(days: 3)) {
    return (t) => '${_two(t.hour)}:${_two(t.minute)}';
  }
  if (totalSpan <= const Duration(days: 70)) {
    return (t) => '${t.day} ${monthAbbrEs[t.month - 1]}';
  }
  if (totalSpan <= const Duration(days: 730)) {
    return (t) => monthAbbrEs[t.month - 1];
  }
  return (t) => '${t.year}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Config resultante para el eje X de una gráfica de tiempo continuo
/// (`fl_chart`'s `LineChartData.minX/maxX`): el `interval` a pasarle a
/// `SideTitles` y una función de formato que recibe el milisegundo bruto
/// de cada marca generada por `fl_chart` y la redondea al escalón elegido
/// antes de darle texto (para que se lea "14:00" y no "14:32").
class TimeAxisConfig {
  const TimeAxisConfig({required this.intervalMs, required this.formatTick});

  final double intervalMs;
  final String Function(double millisSinceEpoch) formatTick;
}

/// Calcula cuántas marcas mostrar en el eje X y con qué formato, a partir
/// del ancho real disponible (para respetar ~[targetPxPerLabel] px entre
/// etiquetas — ni: el nº de datos no importa aquí, todos se siguen
/// dibujando, esto solo decide qué marcas del eje se ven) y del rango
/// temporal [start]-[end] (hora local).
TimeAxisConfig computeTimeAxisConfig({
  required DateTime start,
  required DateTime end,
  required double availableWidthPx,
  double targetPxPerLabel = 80,
}) {
  final totalSpan = end.difference(start);
  final desiredCount = (availableWidthPx / targetPxPerLabel).floor().clamp(2, 10).toInt();
  final idealStepMs = totalSpan.inMilliseconds / (desiredCount - 1);
  final step = _pickTimeStep(idealStepMs);
  final formatter = timeLabelFormatterFor(totalSpan);

  return TimeAxisConfig(
    intervalMs: step.approxMs,
    formatTick: (millis) {
      final raw = DateTime.fromMillisecondsSinceEpoch(millis.round());
      return formatter(_floorTo(raw, step));
    },
  );
}

// ---------------------------------------------------------------------------
// Eje X por índice — gráficas de barras donde cada barra ya representa
// una unidad de tiempo fija (1 barra = 1 día en la gráfica de acumulados
// semana/mes/2 meses): no hace falta redondear fechas, solo decidir cada
// cuántas barras mostrar etiqueta.
// ---------------------------------------------------------------------------

const _indexStepCandidates = [1, 2, 3, 5, 7, 10, 14, 21, 30, 60, 90];

/// Cada cuántos elementos ([totalCount] en total) mostrar etiqueta, para
/// respetar ~[targetPxPerLabel] px entre etiquetas en [availableWidthPx].
int pickIndexStep(int totalCount, double availableWidthPx, {double targetPxPerLabel = 80}) {
  final desiredCount = (availableWidthPx / targetPxPerLabel).floor().clamp(2, totalCount).toInt();
  final idealStep = totalCount / desiredCount;
  for (final c in _indexStepCandidates) {
    if (c >= idealStep) return c;
  }
  return _indexStepCandidates.last;
}
