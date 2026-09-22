import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alerts/presentation/alerts_list_screen.dart';
import '../../features/audit/presentation/audit_log_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/accept_invitation_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/select_organization_screen.dart';
import '../../features/directory/presentation/device_detail_screen.dart';
import '../../features/directory/presentation/directory_screen.dart';
import '../../features/directory/presentation/gateway_detail_screen.dart';
import '../../features/directory/presentation/sensor_detail_screen.dart';
import '../../features/installations/presentation/installation_detail_screen.dart';
import '../../features/installations/presentation/installations_list_screen.dart';
import '../../features/members/presentation/member_sessions_screen.dart';
import '../../features/members/presentation/members_list_screen.dart';
import '../../features/organization/presentation/organization_settings_screen.dart';
import '../../features/platform/presentation/platform_audit_log_screen.dart';
import '../../features/platform/presentation/platform_device_detail_screen.dart';
import '../../features/platform/presentation/platform_gateway_detail_screen.dart';
import '../../features/platform/presentation/platform_installation_detail_screen.dart';
import '../../features/platform/presentation/platform_installations_screen.dart';
import '../../features/platform/presentation/platform_organization_features_screen.dart';
import '../../features/platform/presentation/platform_organizations_screen.dart';
import '../../features/readings/presentation/channel_history_screen.dart';
import '../../features/sessions/presentation/sessions_list_screen.dart';
import '../../features/stations/presentation/station_detail_screen.dart';
import '../../features/stations/presentation/stations_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/locked_feature_screen.dart';

import '../../features/parcels/presentation/draw_parcel_screen.dart';
import '../../features/campaigns/presentation/campaign_detail_screen.dart';
import '../../features/campaigns/presentation/campaigns_screen.dart';
import '../../features/campaigns/presentation/new_campaign_screen.dart';
import '../../features/satellite/presentation/satellite_screen.dart';
import '../widgets/under_construction_screen.dart';

/// Traduce los cambios de `AuthState` (Riverpod) en notificaciones que
/// GoRouter entiende (`Listenable`), para que reevalúe `redirect` cada vez
/// que cambia el estado de sesión sin tener que reconstruir el router entero.
class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) => notifyListeners());
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _GoRouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Enlaces de un solo uso desde email (invitación/restablecer
      // contraseña) — siempre accesibles, independientes del estado de
      // sesión actual (incluso durante el `initial` del bootstrap, para no
      // perder el token de la URL con una redirección a `/` de por medio).
      const tokenActionRoutes = {'/forgot-password', '/accept-invitation', '/reset-password'};
      if (tokenActionRoutes.contains(location)) {
        return null;
      }

      switch (authState.status) {
        case AuthStatus.initial:
          return location == '/' ? null : '/';
        case AuthStatus.unauthenticated:
          return location == '/login' ? null : '/login';
        case AuthStatus.needsOrgSelection:
          return location == '/select-organization' ? null : '/select-organization';
        case AuthStatus.authenticated:
          final isOnAuthRoute = location == '/' || location == '/login' || location == '/select-organization';
          if (!isOnAuthRoute) return null;
          // Un Admin de plataforma "puro" (sin membresía en ninguna
          // organización) entra por el panel de plataforma (`API_DESIGN.md`
          // §2). Desde ahí llega a `/stations`, que para él lista las
          // estaciones de todas las organizaciones (ADR-0007).
          final isPurePlatformAdmin =
              authState.isPlatformAdmin && authState.organizationId == null;
          // Estaciones (BACKLOG.md #30) es el nuevo aterrizaje de un usuario
          // normal de organización — antes era Instalaciones.
          return isPurePlatformAdmin ? '/platform' : '/stations';
      }
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/accept-invitation',
        builder: (context, state) => AcceptInvitationScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/select-organization',
        builder: (context, state) => const SelectOrganizationScreen(),
      ),
      // Menú lateral persistente (Etapa 14 V2, BACKLOG.md #29-#41) — 8 ramas
      // con su propio `Navigator`/back-stack independiente (`goBranch`,
      // AppShell). Todo lo que NO es una de estas 8 pantallas de aterrizaje
      // (detalle de instalación/gateway/dispositivo/sensor, Perfil, panel
      // de plataforma) sigue siendo un `GoRoute` normal fuera del shell, sin
      // cambios: un `context.push(...)` a esas rutas simplemente cubre el
      // menú con una pantalla completa, igual que hacía antes de existir
      // este shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stations',
                builder: (context, state) => const StationsScreen(),
                routes: [
                  // Pantalla de una estación (BACKLOG.md #49, mejora C): dentro de
                  // la rama, así la barra inferior sigue visible y "atrás" vuelve
                  // al resumen.
                  GoRoute(
                    path: ':gatewayId',
                    builder: (context, state) => StationDetailScreen(gatewayId: state.pathParameters['gatewayId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/alerts', builder: (context, state) => const AlertsListScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/custom-charts',
                builder: (context, state) =>
                    const UnderConstructionScreen(title: 'Gráficos personalizados'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) =>
                    const LockedFeatureScreen(featureCode: 'reports_pdf', title: 'Informes'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/campaigns',
                builder: (context, state) => const CampaignsScreen(),
                routes: [
                  // 'new' antes que ':id': si no, 'new' se tomaría por un id.
                  GoRoute(path: 'new', builder: (context, state) => const NewCampaignScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        CampaignDetailScreen(campaignId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pathogens',
                builder: (context, state) => const LockedFeatureScreen(
                  featureCode: 'disease_risk',
                  title: 'Afecciones y patógenos',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/satellite',
                builder: (context, state) => const SatelliteScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/installations', builder: (context, state) => const InstallationsListScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/installations/:id',
        builder: (context, state) => InstallationDetailScreen(
          installationId: state.pathParameters['id']!,
        ),
      ),
      // Dibujo de una parcela: pantalla completa, fuera del shell, porque el
      // mapa necesita todo el alto y las pestanas estorban.
      GoRoute(
        path: '/installations/:id/parcels/new',
        builder: (context, state) =>
            DrawParcelScreen(installationId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/members', builder: (context, state) => const MembersListScreen()),
      GoRoute(
        path: '/members/:id/sessions',
        builder: (context, state) => MemberSessionsScreen(
          memberId: state.pathParameters['id']!,
          memberName: state.extra as String? ?? '',
        ),
      ),
      GoRoute(path: '/sessions', builder: (context, state) => const SessionsListScreen()),
      GoRoute(path: '/audit-log', builder: (context, state) => const AuditLogScreen()),
      GoRoute(
        path: '/organization',
        builder: (context, state) => const OrganizationSettingsScreen(),
      ),
      GoRoute(
        path: '/platform',
        builder: (context, state) => const PlatformOrganizationsScreen(),
      ),
      GoRoute(
        path: '/platform/audit-log',
        builder: (context, state) => const PlatformAuditLogScreen(),
      ),
      GoRoute(
        path: '/platform/organizations/:id/features',
        builder: (context, state) => PlatformOrganizationFeaturesScreen(
          organizationId: state.pathParameters['id']!,
          organizationName: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: '/platform/organizations/:organizationId/installations',
        builder: (context, state) => PlatformInstallationsScreen(
          organizationId: state.pathParameters['organizationId']!,
          organizationName: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: '/platform/organizations/:organizationId/installations/:installationId',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return PlatformInstallationDetailScreen(
            organizationId: state.pathParameters['organizationId']!,
            installationId: state.pathParameters['installationId']!,
            installationName: extra['installationName'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/platform/organizations/:organizationId/gateways/:id',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return PlatformGatewayDetailScreen(
            organizationId: state.pathParameters['organizationId']!,
            gatewayId: state.pathParameters['id']!,
            gatewayName: extra['gatewayName'] as String? ?? '',
            installationId: extra['installationId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/platform/organizations/:organizationId/devices/:id',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return PlatformDeviceDetailScreen(
            organizationId: state.pathParameters['organizationId']!,
            deviceId: state.pathParameters['id']!,
            deviceName: extra['deviceName'] as String? ?? '',
            gatewayId: extra['gatewayId'] as String? ?? '',
            installationId: extra['installationId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/channels/:channelId/history',
        builder: (context, state) => ChannelHistoryScreen(
          channelId: state.pathParameters['channelId']!,
          channelTypeCode: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: '/installations/:id/directory',
        builder: (context, state) => DirectoryScreen(
          installationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/gateways/:id',
        builder: (context, state) => GatewayDetailScreen(gatewayId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/devices/:id',
        builder: (context, state) => DeviceDetailScreen(deviceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sensors/:id',
        builder: (context, state) => SensorDetailScreen(sensorId: state.pathParameters['id']!),
      ),
    ],
  );
});
