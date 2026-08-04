import 'package:flutter/material.dart';

/// Tarjeta única de la plataforma (Etapa 14) — mismo motivo que [AppButton]:
/// centraliza el estilo (radio, borde, elevación) que ya fija `CardTheme`
/// en `app_theme.dart`, y añade el padding/onTap que Flutter no da gratis.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: card,
    );
  }
}
