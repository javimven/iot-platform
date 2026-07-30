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
import '../../features/members/presentation/members_list_screen.dart';
import '../../features/organization/presentation/organization_settings_screen.dart';
import '../../features/readings/presentation/channel_history_screen.dart';
import '../../features/sessions/presentation/sessions_list_screen.dart';

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
          return isOnAuthRoute ? '/installations' : null;
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
      GoRoute(
        path: '/installations',
        builder: (context, state) => const InstallationsListScreen(),
      ),
      GoRoute(
        path: '/installations/:id',
        builder: (context, state) => InstallationDetailScreen(
          installationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(path: '/alerts', builder: (context, state) => const AlertsListScreen()),
      GoRoute(path: '/members', builder: (context, state) => const MembersListScreen()),
      GoRoute(path: '/sessions', builder: (context, state) => const SessionsListScreen()),
      GoRoute(path: '/audit-log', builder: (context, state) => const AuditLogScreen()),
      GoRoute(
        path: '/organization',
        builder: (context, state) => const OrganizationSettingsScreen(),
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
