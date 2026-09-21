import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/organization/application/organization_controller.dart';
import '../theme/app_colors.dart';
import '../theme/theme_preference.dart';

/// Ancho a partir del cual una tableta enseña el menú lateral en vez de la
/// barra inferior. Un teléfono nunca lo hace, aunque girado mida 844 de ancho.
const anchoMenuLateral = 840.0;

/// Por debajo de este ancho el menú lateral se encoge a una fila de iconos: en
/// una ventana pequeña de ordenador, 240 px de menú se comían el sitio de los
/// datos (decisión del usuario, 2026-09-21).
const anchoMenuCompleto = 1100.0;

/// Ancho del menú encogido: un icono de 22 px con sitio para el dedo o el
/// puntero a los lados.
const anchoMenuIconos = 72.0;

/// Un teléfono o una tableta. En web, Flutter deduce la plataforma del
/// navegador, así que un ordenador nunca entra aquí por estrecha que se ponga
/// la ventana: era justo el fallo que se veía (la web de escritorio se
/// comportaba como un móvil tumbado al encoger la ventana).
///
/// Se pasa siempre `Theme.of(context).platform`, no `defaultTargetPlatform` a
/// pelo: es lo mismo en producción y además deja fijarla en una prueba.
bool esMovil([TargetPlatform? platform]) {
  final actual = platform ?? defaultTargetPlatform;
  return actual == TargetPlatform.android || actual == TargetPlatform.iOS;
}

/// Disposición de menú lateral: siempre en ordenador; en móvil, solo en una
/// tableta lo bastante ancha.
bool usaMenuLateral(Size size, {TargetPlatform? platform}) {
  if (!esMovil(platform)) return true;
  return size.width >= anchoMenuLateral && size.shortestSide >= 600;
}

/// Si el menú lateral cabe con sus etiquetas o se queda en iconos.
bool menuLateralCompleto(Size size) => size.width >= anchoMenuCompleto;

/// Un teléfono girado: la pantalla de una estación pasa a enseñar solo la
/// gráfica (BACKLOG.md #49, mejora E). Un ordenador con la ventana apaisada y
/// baja no es esto, por más que las medidas se le parezcan.
bool isPhoneLandscape(Size size, {TargetPlatform? platform}) =>
    esMovil(platform) && size.shortestSide < 600 && size.width > size.height;

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
/// `app_router.dart`. Cada rama sigue trayendo su propio `Scaffold`/`AppBar`.
///
/// - **Móvil**: barra inferior con Estaciones, Alertas, Gráficos y "Más", que
///   abre el resto (secciones, cuenta, apariencia y cerrar sesión) en una hoja.
/// - **Ordenador** (y tableta desde 840 px): menú lateral con todas las
///   secciones y la cuenta a la vista, y el contenido ocupando todo el ancho
///   que queda. En el ordenador hay sitio para los menús y no tiene sentido
///   esconderlos tras "Más", pero las pantallas son las mismas (BACKLOG.md
///   #53 y #56). Por debajo de 1100 px el menú se encoge a iconos para no
///   quitarle ancho a los datos.
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
    final size = MediaQuery.sizeOf(context);
    final platform = Theme.of(context).platform;

    if (usaMenuLateral(size, platform: platform)) {
      return Scaffold(
        body: Row(
          children: [
            _MenuLateral(
              navigationShell: navigationShell,
              entries: _entries,
              compacto: !menuLateralCompleto(size),
            ),
            // Sin ancho máximo: los datos ocupan la pantalla entera
            // (decisión del usuario, 2026-09-21).
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    // Con el teléfono girado en la pantalla de una estación, la gráfica ocupa
    // todo: sin barra inferior. Vuelve al poner el móvil derecho.
    final fullScreenChart =
        isPhoneLandscape(size, platform: platform) && _stationDetailPath.hasMatch(GoRouterState.of(context).uri.path);
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

/// Menú lateral del ordenador: todas las secciones y la cuenta a la vista, sin
/// nada escondido tras un "Más". Mismos destinos que la barra inferior del
/// móvil y la hoja que abre.
class _MenuLateral extends ConsumerWidget {
  const _MenuLateral({
    required this.navigationShell,
    required this.entries,
    required this.compacto,
  });

  final StatefulNavigationShell navigationShell;
  final List<_Section> entries;

  /// Solo iconos: la ventana no da para las etiquetas.
  final bool compacto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final bloqueada = _featureLock(ref);
    final theme = Theme.of(context);

    return Container(
      width: compacto ? anchoMenuIconos : 240,
      color: AppColors.sidebarBackground,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (var i = 0; i < entries.length; i++)
              _EntradaMenu(
                icon: entries[i].icon,
                label: entries[i].label,
                selected: navigationShell.currentIndex == i,
                locked: bloqueada(entries[i].featureCode),
                compacto: compacto,
                onTap: () => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
              ),
            const Divider(color: AppColors.sidebarLine, height: 24),
            // Encogido, la cuenta entera cabe en un icono: cinco entradas con
            // el mismo dibujo de persona no se distinguirían.
            if (compacto) _CuentaCompacta(rutas: _accountRoutes(authState)),
            if (!compacto) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text(
                  'Cuenta',
                  style: theme.textTheme.labelMedium?.copyWith(color: AppColors.sidebarInkSoft),
                ),
              ),
              for (final item in _accountRoutes(authState))
                _EntradaMenu(
                  icon: Icons.person_outline,
                  label: item.label,
                  selected: false,
                  locked: false,
                  onTap: () => context.push(item.route),
                ),
              _EntradaMenu(
                icon: Icons.palette_outlined,
                label: 'Apariencia',
                selected: false,
                locked: false,
                onTap: () => mostrarApariencia(context),
              ),
              const _EntradaMenu(
                icon: Icons.language,
                label: 'Idioma',
                selected: false,
                locked: false,
                onTap: null,
                trailingLabel: 'Próximamente',
              ),
              const Divider(color: AppColors.sidebarLine, height: 24),
              // Separado y en color de peligro, igual que en la hoja del móvil.
              _EntradaMenu(
                icon: Icons.logout,
                label: 'Cerrar sesión',
                selected: false,
                locked: false,
                danger: true,
                onTap: () => ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El diálogo de apariencia, desde el menú ancho o desde el encogido.
void mostrarApariencia(BuildContext context) {
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
}

/// La cuenta cuando el menú está encogido: un icono que despliega lo mismo que
/// el bloque "Cuenta" del menú ancho, cerrar sesión incluido.
class _CuentaCompacta extends ConsumerWidget {
  const _CuentaCompacta({required this.rutas});

  final List<({String route, String label})> rutas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.account_circle_outlined, color: AppColors.sidebarInk, size: 22),
      onSelected: (valor) {
        switch (valor) {
          case _apariencia:
            mostrarApariencia(context);
          case _cerrarSesion:
            ref.read(authControllerProvider.notifier).logout();
          default:
            context.push(valor);
        }
      },
      itemBuilder: (context) => [
        for (final item in rutas)
          PopupMenuItem(
            value: item.route,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(item.label),
            ),
          ),
        const PopupMenuItem(
          value: _apariencia,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_outlined),
            title: Text('Apariencia'),
          ),
        ),
        const PopupMenuItem(
          enabled: false,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language),
            title: Text('Idioma'),
            trailing: Text('Próximamente'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _cerrarSesion,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Cerrar sesión', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
      ],
    );
  }

  // Valores que no son una ruta.
  static const _apariencia = '__apariencia';
  static const _cerrarSesion = '__cerrar-sesion';
}

class _EntradaMenu extends StatelessWidget {
  const _EntradaMenu({
    required this.icon,
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
    this.trailingLabel,
    this.danger = false,
    this.compacto = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;
  final String? trailingLabel;
  final bool danger;

  /// Solo el icono, con la etiqueta en un aviso emergente.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.criticalDark
        : selected
            ? AppColors.sidebarBrand
            : (locked || onTap == null ? AppColors.sidebarInkSoft : AppColors.sidebarInk);

    if (compacto) {
      return Tooltip(
        message: locked ? '$label (no contratado)' : label,
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            height: 48,
            decoration: BoxDecoration(
              color: selected ? AppColors.sidebarSurfaceRaised : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        // 48 px de alto: la misma medida de toque que en el móvil.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.sidebarSurfaceRaised : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
            if (locked) const Icon(Icons.lock_outline, size: 14, color: AppColors.sidebarInkSoft),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.sidebarInkSoft),
              ),
          ],
        ),
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
