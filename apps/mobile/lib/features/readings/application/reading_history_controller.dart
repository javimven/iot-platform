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
enum HistoryRange { day, week, month }

extension HistoryRangeX on HistoryRange {
  String get granularity => switch (this) {
        HistoryRange.day => 'raw',
        HistoryRange.week => 'hourly',
        HistoryRange.month => 'daily',
      };

  Duration get span => switch (this) {
        HistoryRange.day => const Duration(hours: 24),
        HistoryRange.week => const Duration(days: 7),
        HistoryRange.month => const Duration(days: 30),
      };

  String get label => switch (this) {
        HistoryRange.day => '24 h',
        HistoryRange.week => '7 días',
        HistoryRange.month => '30 días',
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
