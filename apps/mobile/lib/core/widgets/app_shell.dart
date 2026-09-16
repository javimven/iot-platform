import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/organization/application/organization_controller.dart';
import '../theme/app_colors.dart';

/// Colapso manual del menú (botón "Contraer menú") — independiente del
/// colapso automático por ancho de ventana estrecho, ambos se combinan en
/// `AppShell`.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

class _SidebarEntry {
  const _SidebarEntry({required this.icon, required this.label, this.featureCode});
  final IconData icon;
  final String label;

  /// Código de `organization_features` que bloquea esta sección si la
  /// organización no lo tiene contratado (BACKLOG.md #33-#36) — null para
  /// las secciones que no dependen de ningún plan.
  final String? featureCode;
}

/// Menú lateral persistente (Etapa 14 V2, BACKLOG.md #29) — envuelve el
/// `StatefulNavigationShell` de `StatefulShellRoute.indexedStack` en
/// `app_router.dart`. Ancho completo (con etiquetas) en ventanas ≥840px;
/// por debajo de eso, o si el usuario lo contrae a mano, se reduce a una
/// barra de solo iconos (nunca desaparece del todo — a diferencia de un
/// `Drawer` oculto, esto no exige un segundo `Scaffold` que "sepa" abrir el
/// cajón del primero, cuando cada rama ya trae su propio `Scaffold`/`AppBar`
/// propio, como el resto de la app).
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _entries = [
    _SidebarEntry(icon: Icons.sensors_outlined, label: 'Estaciones'),
    _SidebarEntry(icon: Icons.notifications_outlined, label: 'Alertas'),
    _SidebarEntry(icon: Icons.show_chart, label: 'Gráficos personalizados'),
    _SidebarEntry(icon: Icons.assignment_outlined, label: 'Informes', featureCode: 'reports_pdf'),
    _SidebarEntry(icon: Icons.eco_outlined, label: 'Campañas', featureCode: 'campaigns'),
    _SidebarEntry(icon: Icons.bug_report_outlined, label: 'Afecciones y patógenos', featureCode: 'disease_risk'),
    _SidebarEntry(icon: Icons.satellite_alt_outlined, label: 'Satélite', featureCode: 'satellite_imagery'),
    _SidebarEntry(icon: Icons.dashboard_outlined, label: 'Infraestructura'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    final manuallyCollapsed = ref.watch(sidebarCollapsedProvider);
    final collapsed = manuallyCollapsed || !isWide;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(collapsed: collapsed, showToggle: isWide, navigationShell: navigationShell, entries: _entries),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.collapsed,
    required this.showToggle,
    required this.navigationShell,
    required this.entries,
  });

  final bool collapsed;
  final bool showToggle;
  final StatefulNavigationShell navigationShell;
  final List<_SidebarEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final canCheckFeatures = authState.roleCode == 'org_admin';
    final features = canCheckFeatures ? ref.watch(organizationFeaturesProvider) : null;

    bool isLocked(String? featureCode) {
      if (featureCode == null) return false;
      if (features == null) return true; // no se puede comprobar -> bloqueado por defecto
      return features.maybeWhen(
        data: (items) => !items.any((f) => f.featureCode == featureCode && f.enabled),
        orElse: () => true,
      );
    }

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
            if (showToggle)
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

/// Icono de Perfil (abajo del todo) — abre el mismo conjunto de pantallas
/// que antes vivía en la `AppBar` de `InstallationsListScreen` (Miembros/
/// Organización/Auditoría/Sesiones), con la misma pista de UI por rol.
/// `isPlatformAdmin` cubre el caso raro de un usuario que además de
/// miembro de una organización es también Admin de plataforma — su único
/// camino hacia `/platform` sigue siendo este menú, igual que antes.
class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({required this.collapsed, required this.authState});

  final bool collapsed;
  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    final roleCode = authState.roleCode;
    final canManageMembers = roleCode == 'org_admin';
    final canSeeOrganization = roleCode == 'org_admin';
    final canSeeAudit = roleCode == 'org_admin' || roleCode == 'technician';
    final isPlatformAdmin = authState.isPlatformAdmin;

    return PopupMenuButton<String>(
      tooltip: 'Perfil',
      onSelected: (route) => context.push(route),
      itemBuilder: (context) => [
        const PopupMenuItem(value: '/sessions', child: Text('Sesiones activas')),
        if (canManageMembers) const PopupMenuItem(value: '/members', child: Text('Miembros')),
        if (canSeeOrganization) const PopupMenuItem(value: '/organization', child: Text('Organización')),
        if (canSeeAudit) const PopupMenuItem(value: '/audit-log', child: Text('Auditoría')),
        if (isPlatformAdmin) const PopupMenuItem(value: '/platform', child: Text('Panel de plataforma')),
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
