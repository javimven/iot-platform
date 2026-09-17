import 'package:flutter/material.dart';

import '../../../core/format/reading_format.dart';
import '../../../core/format/relative_time.dart';
import '../../../core/theme/app_colors.dart';
import '../../installations/data/installation_models.dart';
import '../../readings/application/channel_type_labels.dart';
import '../application/station_health.dart';

/// Cobertura y batería de la estación como iconos, igual que en la barra de un
/// móvil, en vez de gráfica y pestaña propia (petición del usuario, BACKLOG.md
/// #49 F): barras de cobertura según su nivel, y la batería con su tensión.
/// La cobertura débil va en ámbar; el nivel siempre se lee también en texto
/// (lector de pantalla y, con [showDetailOnTap], al tocar).
class StationHealthIcons extends StatelessWidget {
  const StationHealthIcons({required this.readings, this.showDetailOnTap = false, super.key});

  final List<LatestReading> readings;

  /// Al tocar, un aviso con el detalle. Fuera de la tarjeta del resumen, que
  /// entera abre la estación.
  final bool showDetailOnTap;

  @override
  Widget build(BuildContext context) {
    final health = stationHealthOf(readings);
    final signal = health.signal;
    final battery = health.battery;
    if (signal == null && battery == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final soft = theme.colorScheme.onSurfaceVariant;
    final level = signal == null ? null : signalLevelFor(signal.value);
    final batteryText = battery == null
        ? null
        : '${formatReading(battery.value, decimals: 2)} ${ChannelTypeLabels.unitFor(battery.channelTypeCode)}';
    final newest = [signal, battery].whereType<LatestReading>().map((r) => r.tsOrigin).reduce((a, b) => a.isAfter(b) ? a : b);

    final description = [
      if (level != null) 'Cobertura ${level.label} (${formatReading(signal!.value, decimals: 0)} dBm)',
      if (batteryText != null) 'Batería $batteryText',
    ].join('. ');

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (level != null)
          SignalBars(
            level: level,
            active: level == SignalLevel.weak ? (isDark ? AppColors.warnDark : AppColors.warn) : theme.colorScheme.onSurface,
            inactive: theme.colorScheme.outlineVariant,
          ),
        if (level != null && batteryText != null) const SizedBox(width: 10),
        if (batteryText != null) ...[
          Icon(Icons.battery_unknown, size: 18, color: soft),
          const SizedBox(width: 2),
          Text(batteryText, style: theme.textTheme.labelMedium?.copyWith(color: soft, fontFeatures: tabularFigures)),
        ],
      ],
    );

    content = Semantics(label: description, excludeSemantics: true, child: content);
    if (!showDetailOnTap) return content;
    return Tooltip(
      message: '$description\nÚltimo dato ${formatAgo(newest)}',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), child: content),
    );
  }
}

/// Cuatro barras de altura creciente, encendidas según el nivel de cobertura.
class SignalBars extends StatelessWidget {
  const SignalBars({required this.level, required this.active, required this.inactive, super.key});

  final SignalLevel level;
  final Color active;
  final Color inactive;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 14),
      painter: _SignalBarsPainter(bars: level.bars, active: active, inactive: inactive),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  _SignalBarsPainter({required this.bars, required this.active, required this.inactive});

  final int bars;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 4;
    const gap = 2.0;
    final width = (size.width - gap * (count - 1)) / count;
    for (var i = 0; i < count; i++) {
      final height = size.height * (i + 1) / count;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (width + gap), size.height - height, width, height),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, Paint()..color = i < bars ? active : inactive);
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.active != active || oldDelegate.inactive != inactive;
}
