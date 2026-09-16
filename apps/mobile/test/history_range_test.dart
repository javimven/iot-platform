import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/readings/application/reading_history_controller.dart';

/// `twoDays`/`twoMonths` añadidos en Etapa 14 V2 (BACKLOG.md #30, pantalla
/// "Estaciones") — ambos ≤7 días caen en `raw` (MAX_RAW_RANGE_DAYS, backend),
/// igual que `day`.
void main() {
  group('HistoryRangeX', () {
    test('day y twoDays usan granularidad raw (≤7 días, MAX_RAW_RANGE_DAYS)', () {
      expect(HistoryRange.day.granularity, 'raw');
      expect(HistoryRange.twoDays.granularity, 'raw');
    });

    test('week usa granularidad hourly', () {
      expect(HistoryRange.week.granularity, 'hourly');
    });

    test('month y twoMonths usan granularidad daily', () {
      expect(HistoryRange.month.granularity, 'daily');
      expect(HistoryRange.twoMonths.granularity, 'daily');
    });

    test('span de cada preset es el esperado', () {
      expect(HistoryRange.day.span, const Duration(hours: 24));
      expect(HistoryRange.twoDays.span, const Duration(days: 2));
      expect(HistoryRange.week.span, const Duration(days: 7));
      expect(HistoryRange.month.span, const Duration(days: 30));
      expect(HistoryRange.twoMonths.span, const Duration(days: 60));
    });

    test('label de cada preset es el texto en español acordado', () {
      expect(HistoryRange.day.label, '1 día');
      expect(HistoryRange.twoDays.label, '2 días');
      expect(HistoryRange.week.label, '1 semana');
      expect(HistoryRange.month.label, '1 mes');
      expect(HistoryRange.twoMonths.label, '2 meses');
    });
  });
}
