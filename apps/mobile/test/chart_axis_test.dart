import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/stations/presentation/chart_axis.dart';

/// Motor de ejes compartido por las gráficas de Estaciones — cálculo de
/// intervalos "bonitos" del eje Y y de marcas de tiempo del eje X según el
/// ancho disponible (petición explícita: ejes legibles, sin decimales
/// largos ni etiquetas solapadas, en cualquier tamaño de pantalla).
void main() {
  group('computeNiceYAxis', () {
    test('elige un paso redondo (5) en vez de decimales largos, ej. 11.37-24.72', () {
      final axis = computeNiceYAxis(11.37, 24.72);

      expect(axis.step, 5);
      expect(axis.min, lessThanOrEqualTo(11.37));
      expect(axis.max, greaterThanOrEqualTo(24.72));
      expect(axis.decimals, 0);
    });

    test('los límites siempre contienen el rango real de datos', () {
      final axis = computeNiceYAxis(3.2, 97.8);

      expect(axis.min, lessThanOrEqualTo(3.2));
      expect(axis.max, greaterThanOrEqualTo(97.8));
    });

    test('con min == max (todos los valores iguales), no degenera en un eje de ancho 0', () {
      final axis = computeNiceYAxis(20, 20);

      expect(axis.max, greaterThan(axis.min));
      expect(axis.step, greaterThan(0));
    });

    test('un paso fraccionario (ej. 0.5) usa los decimales justos para representarlo', () {
      final axis = computeNiceYAxis(0, 2.3);

      expect(axis.format(axis.step), isNot(contains('.500000')));
    });

    test('el número de divisiones generadas está en el rango 4-8 (apuntando a 5-7)', () {
      final axis = computeNiceYAxis(0, 143);
      final tickCount = ((axis.max - axis.min) / axis.step).round() + 1;

      expect(tickCount, inInclusiveRange(4, 8));
    });
  });

  group('computeTimeAxisConfig — eje X de tiempo continuo', () {
    test('con más ancho disponible, el intervalo elegido es menor (más marcas)', () {
      final start = DateTime(2026, 8, 6, 0);
      final end = DateTime(2026, 8, 7, 0);

      final narrow = computeTimeAxisConfig(start: start, end: end, availableWidthPx: 300);
      final wide = computeTimeAxisConfig(start: start, end: end, availableWidthPx: 900);

      expect(wide.intervalMs, lessThanOrEqualTo(narrow.intervalMs));
    });

    test('rango de horas -> formato HH:mm', () {
      final config = computeTimeAxisConfig(
        start: DateTime(2026, 8, 6, 0),
        end: DateTime(2026, 8, 7, 0),
        availableWidthPx: 400,
      );

      final label = config.formatTick(DateTime(2026, 8, 6, 14, 32).millisecondsSinceEpoch.toDouble());
      expect(label, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('rango de varias semanas -> formato "d MMM" (día + mes abreviado, sin año)', () {
      final config = computeTimeAxisConfig(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 30),
        availableWidthPx: 400,
      );

      final label = config.formatTick(DateTime(2026, 8, 10).millisecondsSinceEpoch.toDouble());
      expect(label, '10 ago');
    });

    test('la marca se redondea al escalón elegido, no a la hora exacta del dato', () {
      // Con un rango de 1 día y ancho medio, el escalón es de varias horas
      // — la etiqueta debe leerse "en punto", no "14:32".
      final config = computeTimeAxisConfig(
        start: DateTime(2026, 8, 6, 0),
        end: DateTime(2026, 8, 7, 0),
        availableWidthPx: 400,
      );

      final label = config.formatTick(DateTime(2026, 8, 6, 14, 32).millisecondsSinceEpoch.toDouble());
      expect(label, isNot(endsWith(':32')));
    });
  });

  group('pickIndexStep — eje X por índice (1 barra = 1 día)', () {
    test('con pocas barras y ancho amplio, muestra todas (paso 1)', () {
      expect(pickIndexStep(8, 900), 1);
    });

    test('con muchas barras (2 meses) en un ancho estrecho, agrupa el paso hacia arriba', () {
      final step = pickIndexStep(60, 320);
      expect(step, greaterThan(1));
    });

    test('nunca deja un paso mayor que el propio total de elementos', () {
      final step = pickIndexStep(5, 100);
      expect(step, lessThanOrEqualTo(5));
    });
  });
}
