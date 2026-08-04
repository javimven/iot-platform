import 'package:flutter/material.dart';

/// Variante visual de [AppButton] — `danger` para acciones destructivas
/// (deshabilitar/eliminar), coherente con los diálogos de confirmación ya
/// existentes en el Directorio IoT y Miembros.
enum AppButtonVariant { primary, secondary, danger }

/// Botón único de la plataforma (Etapa 14) — nunca usar `ElevatedButton`/
/// `TextButton` sueltos con estilo a mano en una pantalla; todo botón visible
/// pasa por aquí para que un cambio de estilo futuro sea barato (una sola
/// definición, no una búsqueda por todo el código).
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (background, foreground) = switch (variant) {
      AppButtonVariant.primary => (colorScheme.primary, colorScheme.onPrimary),
      AppButtonVariant.secondary => (colorScheme.surface, colorScheme.primary),
      AppButtonVariant.danger => (colorScheme.error, colorScheme.onError),
    };

    final style = FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: variant == AppButtonVariant.secondary
            ? BorderSide(color: colorScheme.outline)
            : BorderSide.none,
      ),
    );

    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final button = FilledButton(onPressed: onPressed, style: style, child: child);

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
