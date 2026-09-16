import 'package:flutter/material.dart';

import 'app_button.dart';

/// Error con salida: qué ha fallado, un botón para reintentar y el detalle
/// técnico en pequeño para poder diagnosticarlo con una captura (BACKLOG.md
/// #49, mejora H).
class RetryMessage extends StatelessWidget {
  const RetryMessage({required this.message, required this.onRetry, this.technicalDetail, super.key});

  final String message;
  final VoidCallback onRetry;
  final String? technicalDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          AppButton(label: 'Reintentar', icon: Icons.refresh, variant: AppButtonVariant.secondary, onPressed: onRetry),
          if (technicalDetail != null) ...[
            const SizedBox(height: 8),
            Text(
              technicalDetail!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
