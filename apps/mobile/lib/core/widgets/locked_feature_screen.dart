import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/organization/application/organization_controller.dart';

/// Sección del menú lateral gated por `organization_features` (Informes,
/// Campañas, Afecciones y patógenos, Satélite — BACKLOG.md #33-#36). Nunca
/// se oculta, solo dice si el plan de la organización ya la incluye o no —
/// mismo mecanismo que ya usa `organization_settings_screen.dart` para
/// "Activa / No disponible en tu plan".
///
/// `org_features.read` solo lo tiene `org_admin` (permissions.ts) — para el
/// resto de roles no se llama al endpoint (evita un 403 innecesario) y se
/// asume bloqueado por defecto; es cosmético, la función en sí se sigue
/// comportando igual para cualquier rol.
class LockedFeatureScreen extends ConsumerWidget {
  const LockedFeatureScreen({required this.featureCode, required this.title, super.key});

  final String featureCode;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canCheck = roleCode == 'org_admin';
    final features = canCheck ? ref.watch(organizationFeaturesProvider) : null;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: features == null
              ? Text(
                  '$title no está disponible en tu plan. Contacta con tu administrador.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              : features.when(
                  data: (items) {
                    final enabled = items.any((f) => f.featureCode == featureCode && f.enabled);
                    return Text(
                      enabled
                          ? '$title ya está disponible en tu plan — construcción pendiente.'
                          : '$title no está disponible en tu plan.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    );
                  },
                  error: (_, __) => const Text('No se pudo comprobar tu plan.'),
                  loading: () => const CircularProgressIndicator(),
                ),
        ),
      ),
    );
  }
}
