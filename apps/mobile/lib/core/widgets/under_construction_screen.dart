import 'package:flutter/material.dart';

/// Placeholder para secciones del menú lateral todavía sin construir de
/// verdad (Etapa 14 V2, BACKLOG.md #29-#41) — nunca oculta la sección, solo
/// avisa de que está en construcción.
class UnderConstructionScreen extends StatelessWidget {
  const UnderConstructionScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'En construcción — disponible próximamente.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
