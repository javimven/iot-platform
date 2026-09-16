import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/readings/application/reading_history_controller.dart';
import 'package:iot_platform_app/features/readings/data/reading_history_models.dart';
import 'package:iot_platform_app/features/stations/application/accumulated_slots.dart';

/// `buildAccumulatedSlots` (BACKLOG.md #30, gráfica "de acumulados" de
/// Estaciones): franjas fijas de 6h en hora local para 1 día/2 días (solo
/// las ya completadas, nunca una futura), y una franja por día en UTC para
/// semana/mes/2 meses (sobre el rango completo, huecos incluidos con 0).
/// `now` se fija explícitamente en cada test — sin esto el resultado
/// dependería de a qué hora se ejecute `flutter test`.
void main() {
  group('buildAccumulatedSlots — HistoryRange.day', () {
    HistoryPoint localPoint(DateTime day, int hour, int minute, double value) =>
        HistoryPoint(tsOrigin: DateTime(day.year, day.month, day.day, hour, minute), value: value, min: null, max: null);

    test('a las 13:00, solo aparecen las franjas 0-6 y 6-12 (ya completadas)', () {
      final today = DateTime(2026, 8, 6);
      final now = DateTime(2026, 8, 6, 13, 0);
      final points = [
        localPoint(today, 1, 0, 1.0),
        localPoint(today, 9, 0, 2.0),
        localPoint(today, 13, 0, 3.0), // dentro de la franja 12-18, todavía no completada
      ];

      final slots = buildAccumulatedSlots(points, HistoryRange.day, now: now);

      expect(slots.length, 2);
      expect(slots[0].start, DateTime(2026, 8, 6, 0));
      expect(slots[0].value, 1.0);
      expect(slots[1].start, DateTime(2026, 8, 6, 6));
      expect(slots[1].value, 2.0);
    });

    test('la franja 18-24 nunca aparece en el rango "1 día" — termina justo cuando "hoy" cambia de día', () {
      // Consecuencia lógica, no un caso especial: "1 día" siempre es HOY
      // relativo a `now`. La franja 18-24 solo está "completada" a partir de
      // medianoche — pero en ese mismo instante "hoy" ya es el día
      // siguiente, así que la franja 18-24 del día anterior deja de
      // pertenecer al rango consultado. Para verla completa hay que mirar
      // ese día como "ayer" con `HistoryRange.twoDays` (test de abajo).
      final today = DateTime(2026, 8, 6);
      final points = [
        localPoint(today, 2, 0, 1.0),
        localPoint(today, 8, 0, 2.0),
        localPoint(today, 14, 0, 3.0),
        localPoint(today, 20, 0, 4.0),
      ];

      final slotsAt2359 = buildAccumulatedSlots(points, HistoryRange.day, now: DateTime(2026, 8, 6, 23, 59));
      expect(slotsAt2359.length, 3);
      expect(slotsAt2359.map((s) => s.value), [1.0, 2.0, 3.0]);
    });

    test('suma varias lecturas dentro de la misma franja de 6h, y reserva las franjas vacías con valor 0', () {
      final today = DateTime(2026, 8, 6);
      final now = DateTime(2026, 8, 6, 13, 0);
      final points = [
        localPoint(today, 1, 0, 1.0),
        localPoint(today, 3, 30, 0.5),
        localPoint(today, 5, 59, 0.5),
      ];

      final slots = buildAccumulatedSlots(points, HistoryRange.day, now: now);

      // A las 13h han terminado las franjas 0-6 y 6-12 — la primera con la
      // suma de las 3 lecturas, la segunda vacía (0), pero presente.
      expect(slots.length, 2);
      expect(slots[0].value, 2.0);
      expect(slots[1].value, 0.0);
    });

  });

  group('buildAccumulatedSlots — HistoryRange.twoDays', () {
    test('incluye ayer completo (4 franjas) + hoy hasta la hora actual', () {
      final now = DateTime(2026, 8, 6, 13, 0);
      final points = [
        HistoryPoint(tsOrigin: DateTime(2026, 8, 5, 2, 0), value: 5.0, min: null, max: null), // ayer, franja 0-6
        HistoryPoint(tsOrigin: DateTime(2026, 8, 6, 1, 0), value: 1.0, min: null, max: null), // hoy, franja 0-6
      ];

      final slots = buildAccumulatedSlots(points, HistoryRange.twoDays, now: now);

      // Ayer: 4 franjas completas. Hoy a las 13h: solo 0-6 y 6-12. Total 6.
      expect(slots.length, 6);
      expect(slots.first.start, DateTime(2026, 8, 5, 0));
      expect(slots.first.value, 5.0);
      expect(slots[4].start, DateTime(2026, 8, 6, 0));
      expect(slots[4].value, 1.0);
    });
  });

  group('buildAccumulatedSlots — semana/mes/2 meses', () {
    test('reserva una franja por cada día del rango completo, aunque no tenga datos (UTC)', () {
      final now = DateTime.utc(2026, 8, 6, 10, 0);
      final points = [
        HistoryPoint(tsOrigin: DateTime.utc(2026, 8, 1), value: 3.0, min: null, max: null),
        // 2026-08-02 a 2026-08-05 sin lecturas — deben aparecer con 0, no desaparecer.
        HistoryPoint(tsOrigin: DateTime.utc(2026, 8, 6), value: 7.0, min: null, max: null),
      ];

      final slots = buildAccumulatedSlots(points, HistoryRange.week, now: now);

      // HistoryRange.week.span = 7 días -> from = 2026-07-30, to = 2026-08-06 -> 8 franjas.
      expect(slots.length, 8);
      expect(slots.first.start, DateTime.utc(2026, 7, 30));
      expect(slots.first.value, 0);
      expect(slots.last.start, DateTime.utc(2026, 8, 6));
      expect(slots.last.value, 7.0);
      final aug1 = slots.firstWhere((s) => s.start == DateTime.utc(2026, 8, 1));
      expect(aug1.value, 3.0);
    });

    test('sin ningún punto, sigue devolviendo todas las franjas del rango con valor 0', () {
      final now = DateTime.utc(2026, 8, 6);
      final slots = buildAccumulatedSlots(const [], HistoryRange.month, now: now);

      expect(slots, isNotEmpty);
      expect(slots.every((s) => s.value == 0), isTrue);
    });
  });
}
