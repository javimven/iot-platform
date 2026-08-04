import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Tono semántico de [StatusChip] — deliberadamente distinto del color de
/// marca (`AppColors.brand`), para que "todo bien" nunca se confunda
/// visualmente con el acento corporativo (app_colors.dart).
enum AppStatusTone { ok, warn, critical, neutral }

/// Chip de estado (Etapa 14) — para online/offline de gateway/dispositivo
/// y para el ciclo de vida de una alerta (abierta/reconocida/resuelta,
/// PERMISSIONS.md §3). El estado se codifica en color Y en texto: nunca
/// solo color, para no depender de que el usuario distinga tonos.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.tone, super.key});

  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final color = switch (tone) {
      AppStatusTone.ok => isDark ? AppColors.okDark : AppColors.ok,
      AppStatusTone.warn => isDark ? AppColors.warnDark : AppColors.warn,
      AppStatusTone.critical => isDark ? AppColors.criticalDark : AppColors.critical,
      AppStatusTone.neutral => isDark ? AppColors.inkSoftDark : AppColors.inkSoft,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
