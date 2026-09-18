import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/organization/application/organization_controller.dart';
import '../theme/theme_preference.dart';

/// Un teléfono girado: la pantalla de una estación pasa a enseñar solo la
/// gráfica (BACKLOG.md #49, mejora E).
bool isPhoneLandscape(Size size) => size.shortestSide < 600 && size.width > size.height;

/// La ruta de la pantalla de una estación (`/stations/<id>`).
final _stationDetailPath = RegExp(r'^/stations/[^/]+$');

/// Ramas que van directamente en la barra inferior del móvil: Estaciones,
/// Alertas y Gráficos. El resto se abre desde "Más".
const bottomBarBranchCount = 3;

class _Section {
  const _Section({required this.icon, required this.label, this.shortLabel, this.featureCode});
  final IconData icon;
  final String label;

  /// Etiqueta de la barra inferior, donde no cabe la larga.
  final String? shortLabel;

  /// Código de `organization_features` que bloquea esta sección si la
  /// organización no lo tiene contratado (BACKLOG.md #33-#36) — null para
  /// las secciones que no dependen de ningún plan.
  final String? featureCode;
}

/// Índice de la barra inferior para la rama activa: las tres primeras ramas
/// tienen su propio botón y cualquier otra marca "Más".
int bottomBarIndexFor(int branchIndex) => branchIndex < bottomBarBranchCount ? branchIndex : bottomBarBranchCount;

/// Contenedor de las secciones (Etapa 14 V2, BACKLOG.md #29) — envuelve el
/// `StatefulNavigationShell` de `StatefulShellRoute.indexedStack` en
/// `app_router.dart`. Barra inferior con Estaciones, Alertas, Gráficos y
/// "Más", que abre el resto (secciones, cuenta, apariencia y cerrar sesión)
/// en una hoja inferior. Cada rama sigue trayendo su propio
/// `Scaffold`/`AppBar`.
///
/// La misma disposición en todos los tamaños, también en el ordenador
/// (decisión del usuario, 2026-09-18): antes, a partir de 840 px de ancho
/// había menú lateral y vista de escritorio, y prefiere la del móvil, con sus
/// tarjetas y sus gráficas grandes, en una sola vista que mantener.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _entries = [
    _Section(icon: Icons.sensors_outlined, label: 'Estaciones'),
    _Section(icon: Icons.notifications_outlined, label: 'Alertas'),
    _Section(icon: Icons.show_chart, label: 'Gráficos personalizados', shortLabel: 'Gráficos'),
    _Section(icon: Icons.assignment_outlined, label: 'Informes', featureCode: 'reports_pdf'),
    _Section(icon: Icons.eco_outlined, label: 'Campañas', featureCode: 'campaigns'),
    _Section(icon: Icons.bug_report_outlined, label: 'Afecciones y patógenos', featureCode: 'disease_risk'),
    _Section(icon: Icons.satellite_alt_outlined, label: 'Satélite', featureCode: 'satellite_imagery'),
    _Section(icon: Icons.dashboard_outlined, label: 'Infraestructura'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Con el teléfono girado en la pantalla de una estación, la gráfica ocupa
    // todo: sin barra inferior. Vuelve al poner el móvil derecho.
    final size = MediaQuery.sizeOf(context);
    final fullScreenChart = isPhoneLandscape(size) && _stationDetailPath.hasMatch(GoRouterState.of(context).uri.path);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: fullScreenChart
          ? null
          : NavigationBar(
              selectedIndex: bottomBarIndexFor(navigationShell.currentIndex),
              onDestinationSelected: (index) {
                if (index == bottomBarBranchCount) {
                  _showMoreSheet(context);
                  return;
                }
                navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
              },
              destinations: [
                for (final entry in _entries.take(bottomBarBranchCount))
                  NavigationDestination(icon: Icon(entry.icon), label: entry.shortLabel ?? entry.label),
                const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Más'),
              ],
            ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _MoreSheet(
        entries: _entries.skip(bottomBarBranchCount).toList(),
        firstBranchIndex: bottomBarBranchCount,
        currentBranchIndex: navigationShell.currentIndex,
        onOpenBranch: (index) {
          Navigator.of(sheetContext).pop();
          navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
        },
        onOpenRoute: (route) {
          Navigator.of(sheetContext).pop();
          context.push(route);
        },
      ),
    );
  }
}

/// Si una sección está bloqueada por no tenerla contratada la organización.
/// Solo el Admin de organización puede consultar las funciones contratadas;
/// para el resto se muestra bloqueada por defecto, igual que antes.
bool Function(String? featureCode) _featureLock(WidgetRef ref) {
  final authState = ref.watch(authControllerProvider);
  final features = authState.roleCode == 'org_admin' ? ref.watch(organizationFeaturesProvider) : null;
  return (featureCode) {
    if (featureCode == null) return false;
    if (features == null) return true;
    return features.maybeWhen(
      data: (items) => !items.any((f) => f.featureCode == featureCode && f.enabled),
      orElse: () => true,
    );
  };
}

/// Entradas de cuenta según el rol, en la hoja "Más".
List<({String route, String label})> _accountRoutes(AuthState authState) {
  final roleCode = authState.roleCode;
  return [
    (route: '/sessions', label: 'Sesiones activas'),
    if (roleCode == 'org_admin') (route: '/members', label: 'Miembros'),
    if (roleCode == 'org_admin') (route: '/organization', label: 'Organización'),
    if (roleCode == 'org_admin' || roleCode == 'technician') (route: '/audit-log', label: 'Auditoría'),
    // Un Admin de plataforma que además es miembro llega aquí a su panel.
    if (authState.isPlatformAdmin) (route: '/platform', label: 'Panel de plataforma'),
  ];
}

class _MoreSheet extends ConsumerWidget {
  const _MoreSheet({
    required this.entries,
    required this.firstBranchIndex,
    required this.currentBranchIndex,
    required this.onOpenBranch,
    required this.onOpenRoute,
  });

  final List<_Section> entries;
  final int firstBranchIndex;
  final int currentBranchIndex;
  final void Function(int branchIndex) onOpenBranch;
  final void Function(String route) onOpenRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isLocked = _featureLock(ref);
    final colorScheme = Theme.of(context).colorScheme;
    final sectionStyle = Theme.of(context).textTheme.titleSmall;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (var i = 0; i < entries.length; i++)
          ListTile(
            leading: Icon(entries[i].icon),
            title: Text(entries[i].label),
            trailing: isLocked(entries[i].featureCode) ? const Icon(Icons.lock_outline, size: 18) : null,
            selected: currentBranchIndex == firstBranchIndex + i,
            onTap: () => onOpenBranch(firstBranchIndex + i),
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Cuenta', style: sectionStyle),
        ),
        for (final item in _accountRoutes(authState))
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(item.label),
            onTap: () => onOpenRoute(item.route),
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Apariencia', style: sectionStyle),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ThemePreferenceSelector(),
        ),
        const ListTile(
          leading: Icon(Icons.language),
          title: Text('Idioma'),
          trailing: Text('Próximamente'),
          enabled: false,
        ),
        const Divider(height: 24),
        // Separado del resto y en color de peligro: no se pulsa por accidente
        // buscando otra opción.
        ListTile(
          leading: Icon(Icons.logout, color: colorScheme.error),
          title: Text('Cerrar sesión', style: TextStyle(color: colorScheme.error)),
          onTap: () {
            Navigator.of(context).pop();
            ref.read(authControllerProvider.notifier).logout();
          },
        ),
      ],
    );
  }
}
