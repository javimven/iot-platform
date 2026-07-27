import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/readings/data/reading_history_models.dart';

/// FUNCTIONAL_REQUIREMENTS.md §12: `min`/`max` solo llegan agregados
/// (hourly/daily) en canales de tipo media; en crudo o canales de tipo
/// suma/conteo, ausentes — el modelo debe tolerar ambos casos.
void main() {
  group('HistoryPoint.fromJson', () {
    test('parsea un punto agregado con min/max', () {
      final point = HistoryPoint.fromJson({
        'tsOrigin': '2026-07-27T10:00:00.000Z',
        'value': 21.5,
        'min': 18.0,
        'max': 24.0,
      });

      expect(point.value, 21.5);
      expect(point.min, 18.0);
      expect(point.max, 24.0);
    });

    test('parsea un punto en crudo sin min/max', () {
      final point = HistoryPoint.fromJson({
        'tsOrigin': '2026-07-27T10:00:00.000Z',
        'value': 21.5,
        'min': null,
        'max': null,
      });

      expect(point.value, 21.5);
      expect(point.min, isNull);
      expect(point.max, isNull);
    });
  });
}
