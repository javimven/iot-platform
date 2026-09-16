import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/relative_time.dart';
import '../../../core/theme/app_colors.dart';
import '../application/station_detail_controller.dart';

/// Aviso de una estación que no está enviando o que envía sin datos de sus
/// sensores (BACKLOG.md #49, mejora F). Sin aviso si todo va bien.
class StationDataNotice extends StatelessWidget {
  const StationDataNotice({required this.state, required this.since, super.key});

  final StationDataState state;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    if (state == StationDataState.ok) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ago = since == null ? '' : ' desde ${formatAgo(since!)}';
    final (text, tone, ink) = switch (state) {
      StationDataState.offline => (
          'No envía datos$ago. Si sigue así, comprueba la batería y la cobertura de la estación.',
          isDark ? AppColors.criticalDark : AppColors.critical,
          isDark ? AppColors.criticalInkDark : AppColors.criticalInk,
        ),
      _ => (
          'Envía, pero sin datos de sus sensores$ago. Suele pasar tras un reinicio o quedarse sin batería: '
              'hay que volver a declarar los sensores en la estación.',
          isDark ? AppColors.warnDark : AppColors.warn,
          isDark ? AppColors.warnInkDark : AppColors.warnInk,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: ink),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ink))),
        ],
      ),
    );
  }
}

/// «Sin datos desde hace 25 min» bajo el valor de una magnitud que se ha
/// quedado atrás (un sensor que ha dejado de contestar).
class StaleReadingNote extends StatelessWidget {
  const StaleReadingNote({required this.since, super.key});

  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      'Sin datos desde ${formatAgo(since)}',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isDark ? AppColors.warnInkDark : AppColors.warnInk),
    );
  }
}

/// Refresca los datos de Estaciones cada pocos minutos mientras la pantalla
/// está abierta, y al volver a la app (BACKLOG.md #49, mejora F). La estación
/// envía cada 5 minutos: cada 2 se ve el dato nuevo sin hacer nada.
class StationsAutoRefresh extends ConsumerStatefulWidget {
  const StationsAutoRefresh({required this.child, this.interval = const Duration(minutes: 2), super.key});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<StationsAutoRefresh> createState() => _StationsAutoRefreshState();
}

class _StationsAutoRefreshState extends ConsumerState<StationsAutoRefresh> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => refreshStationData(ref));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshStationData(ref);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
