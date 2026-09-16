import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/reading_history_models.dart';
import '../data/readings_api.dart';

final readingsApiProvider = Provider<ReadingsApi>(
  (ref) => ReadingsApi(ref.watch(apiClientProvider)),
);

/// Presets de rango (FUNCTIONAL_REQUIREMENTS.md §12): cada uno fija tanto la
/// ventana de tiempo como la granularidad — el usuario elige "cuánto quiero
/// ver", nunca la función de agregación directamente (API_DESIGN.md §8).
/// `twoDays`/`twoMonths` añadidos en Etapa 14 V2 (BACKLOG.md #30) para la
/// pantalla "Estaciones" — reutilizados aquí en vez de duplicar el enum.
enum HistoryRange { day, twoDays, week, month, twoMonths }

extension HistoryRangeX on HistoryRange {
  String get granularity => switch (this) {
        HistoryRange.day || HistoryRange.twoDays => 'raw', // ambos ≤7 días (MAX_RAW_RANGE_DAYS)
        HistoryRange.week => 'hourly',
        HistoryRange.month || HistoryRange.twoMonths => 'daily',
      };

  Duration get span => switch (this) {
        HistoryRange.day => const Duration(hours: 24),
        HistoryRange.twoDays => const Duration(days: 2),
        HistoryRange.week => const Duration(days: 7),
        HistoryRange.month => const Duration(days: 30),
        HistoryRange.twoMonths => const Duration(days: 60),
      };

  String get label => switch (this) {
        HistoryRange.day => '1 día',
        HistoryRange.twoDays => '2 días',
        HistoryRange.week => '1 semana',
        HistoryRange.month => '1 mes',
        HistoryRange.twoMonths => '2 meses',
      };
}

/// Estado global (no por canal, igual que `alertStatusFilterProvider`): el
/// usuario suele mirar un canal a la vez, no varios simultáneamente.
final historyRangeProvider = StateProvider<HistoryRange>((ref) => HistoryRange.day);

final channelHistoryProvider =
    FutureProvider.autoDispose.family<List<HistoryPoint>, String>((ref, channelId) {
  final range = ref.watch(historyRangeProvider);
  final to = DateTime.now().toUtc();
  final from = to.subtract(range.span);
  return ref.watch(readingsApiProvider).history(
        channelId: channelId,
        from: from,
        to: to,
        granularity: range.granularity,
      );
});
