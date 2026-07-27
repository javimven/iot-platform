import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alerts/presentation/alerts_list_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/select_organization_screen.dart';
import '../../features/installations/presentation/installation_detail_screen.dart';
import '../../features/installations/presentation/installations_list_screen.dart';
import '../../features/readings/presentation/channel_history_screen.dart';

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
      GoRoute(
        path: '/channels/:channelId/history',
        builder: (context, state) => ChannelHistoryScreen(
          channelId: state.pathParameters['channelId']!,
          channelTypeCode: state.extra as String? ?? '',
        ),
      ),
    ],
  );
});
