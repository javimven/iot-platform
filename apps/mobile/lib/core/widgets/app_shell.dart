import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/organization/application/organization_controller.dart';
import '../theme/app_colors.dart';
import '../theme/theme_preference.dart';

/// Colapso manual del menú (botón "Contraer menú") — solo en pantallas
/// anchas, donde se muestra el menú lateral.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Por debajo de este ancho la navegación va en una barra inferior en vez del
/// menú lateral (BACKLOG.md #49, mejora A).
const compactShellBreakpoint = 840.0;

/// Ramas que van directamente en la barra inferior del móvil: Estaciones,
/// Alertas y Gráficos. El resto se abre desde "Más".
const bottomBarBranchCount = 3;

class _SidebarEntry {
  const _SidebarEntry({required this.icon, required this.label, this.shortLabel, this.featureCode});
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
/// `app_router.dart`. En pantallas anchas, menú lateral persistente (con
/// etiquetas, contraíble a iconos). En el móvil, barra inferior con
/// Estaciones, Alertas, Gráficos y "Más", que abre el resto (secciones,
/// cuenta, apariencia y cerrar sesión) en una hoja inferior. Cada rama sigue
/// trayendo su propio `Scaffold`/`AppBar`.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _entries = [
    _SidebarEntry(icon: Icons.sensors_outlined, label: 'Estaciones'),
    _SidebarEntry(icon: Icons.notifications_outlined, label: 'Alertas'),
    _SidebarEntry(icon: Icons.show_chart, label: 'Gráficos personalizados', shortLabel: 'Gráficos'),
    _SidebarEntry(icon: Icons.assignment_outlined, label: 'Informes', featureCode: 'reports_pdf'),
    _SidebarEntry(icon: Icons.eco_outlined, label: 'Campañas', featureCode: 'campaigns'),
    _SidebarEntry(icon: Icons.bug_report_outlined, label: 'Afecciones y patógenos', featureCode: 'disease_risk'),
    _SidebarEntry(icon: Icons.satellite_alt_outlined, label: 'Satélite', featureCode: 'satellite_imagery'),
    _SidebarEntry(icon: Icons.dashboard_outlined, label: 'Infraestructura'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= compactShellBreakpoint;

    if (!isWide) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
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

    final collapsed = ref.watch(sidebarCollapsedProvider);
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(collapsed: collapsed, navigationShell: navigationShell, entries: _entries),
          Expanded(child: navigationShell),
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

/// Entradas de cuenta según el rol, compartidas por el menú de perfil del
/// escritorio y la hoja "Más" del móvil.
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

  final List<_SidebarEntry> entries;
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

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.collapsed,
    required this.navigationShell,
    required this.entries,
  });

  final bool collapsed;
  final StatefulNavigationShell navigationShell;
  final List<_SidebarEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isLocked = _featureLock(ref);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: collapsed ? 72 : 240,
      color: AppColors.sidebarBackground,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _SidebarItem(
                      entry: entries[i],
                      collapsed: collapsed,
                      selected: navigationShell.currentIndex == i,
                      locked: isLocked(entries[i].featureCode),
                      onTap: () =>
                          navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.sidebarLine, height: 1),
            _SidebarActionItem(
              icon: collapsed ? Icons.chevron_right : Icons.chevron_left,
              label: collapsed ? 'Expandir' : 'Contraer menú',
              collapsed: collapsed,
              onTap: () => ref.read(sidebarCollapsedProvider.notifier).state = !collapsed,
            ),
            _SidebarActionItem(
              icon: Icons.language,
              label: 'Idioma',
              collapsed: collapsed,
              trailingLabel: 'Próximamente',
              onTap: null,
            ),
            _SidebarActionItem(
              icon: Icons.logout,
              label: 'Cerrar sesión',
              collapsed: collapsed,
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
            ),
            _ProfileMenuButton(collapsed: collapsed, authState: authState),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.entry,
    required this.collapsed,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final _SidebarEntry entry;
  final bool collapsed;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.sidebarBrand : (locked ? AppColors.sidebarInkSoft : AppColors.sidebarInk);
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        );

    return Tooltip(
      message: collapsed ? entry.label : '',
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.sidebarSurfaceRaised : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(entry.icon, color: foreground, size: 22),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(child: Text(entry.label, style: textStyle)),
                if (locked) const Icon(Icons.lock_outline, size: 14, color: AppColors.sidebarInkSoft),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarActionItem extends StatelessWidget {
  const _SidebarActionItem({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.trailingLabel,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback? onTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled ? AppColors.sidebarInk : AppColors.sidebarInkSoft;

    return Tooltip(
      message: collapsed ? label : '',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 20),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground)),
                ),
                if (trailingLabel != null)
                  Text(
                    trailingLabel!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.sidebarInkSoft),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Icono de Perfil (abajo del todo, escritorio) — Miembros/Organización/
/// Auditoría/Sesiones con la misma pista de UI por rol, el panel de
/// plataforma si procede, y la apariencia.
class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({required this.collapsed, required this.authState});

  static const _appearance = '#apariencia';

  final bool collapsed;
  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Perfil',
      onSelected: (value) {
        if (value == _appearance) {
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Apariencia'),
              content: const ThemePreferenceSelector(),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cerrar')),
              ],
            ),
          );
          return;
        }
        context.push(value);
      },
      itemBuilder: (context) => [
        for (final item in _accountRoutes(authState)) PopupMenuItem(value: item.route, child: Text(item.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: _appearance, child: Text('Apariencia')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.sidebarSurfaceRaised,
              child: Icon(Icons.person_outline, color: AppColors.sidebarInk, size: 18),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Perfil',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sidebarInk),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
