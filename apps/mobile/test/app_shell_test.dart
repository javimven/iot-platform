import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iot_platform_app/core/api/api_client.dart';
import 'package:iot_platform_app/core/storage/secure_token_storage.dart';
import 'package:iot_platform_app/core/theme/theme_preference.dart';
import 'package:iot_platform_app/core/widgets/app_shell.dart';
import 'package:iot_platform_app/features/auth/application/auth_controller.dart';
import 'package:iot_platform_app/features/auth/application/auth_state.dart';
import 'package:iot_platform_app/features/auth/data/auth_api.dart';

/// Navegación (BACKLOG.md #49, mejora A): barra inferior en el móvil y menú
/// lateral en pantallas anchas, con las mismas secciones.
class _SignedInAuthController extends AuthController {
  _SignedInAuthController() : super(AuthApi(ApiClient()), SecureTokenStorage()) {
    state = const AuthState(status: AuthStatus.authenticated, organizationId: 'org-1', roleCode: 'operator');
  }
}

class _MemoryStore implements PreferenceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _branches = [
  '/stations',
  '/alerts',
  '/custom-charts',
  '/reports',
  '/campaigns',
  '/pathogens',
  '/satellite',
  '/infrastructure',
];

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/stations',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          for (final path in _branches)
            StatefulShellBranch(
              routes: [GoRoute(path: path, builder: (context, state) => Scaffold(body: Text('Pantalla $path')))],
            ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _SignedInAuthController()),
        preferenceStoreProvider.overrideWithValue(_MemoryStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('la barra inferior marca "Más" para cualquier sección que no tiene botón propio', () {
    expect(bottomBarIndexFor(0), 0);
    expect(bottomBarIndexFor(2), 2);
    expect(bottomBarIndexFor(3), 3);
    expect(bottomBarIndexFor(7), 3);
  });

  testWidgets('en el móvil: barra inferior con Estaciones, Alertas, Gráficos y Más', (tester) async {
    await _pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Estaciones', 'Alertas', 'Gráficos', 'Más']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget);
    }
    expect(find.text('Contraer menú'), findsNothing);

    await tester.tap(find.text('Alertas'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla /alerts'), findsOneWidget);
  });

  testWidgets('"Más" abre el resto: secciones, cuenta, apariencia y cerrar sesión', (tester) async {
    await _pumpShell(tester, const Size(390, 844));

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
    for (final label in ['Infraestructura', 'Informes', 'Sesiones activas', 'Apariencia', 'Cerrar sesión']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(ThemePreferenceSelector), findsOneWidget);

    await tester.tap(find.text('Infraestructura'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla /infrastructure'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing); // la hoja se ha cerrado
  });

  testWidgets('en pantalla ancha: menú lateral, sin barra inferior', (tester) async {
    await _pumpShell(tester, const Size(1280, 800));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Gráficos personalizados'), findsOneWidget);
    expect(find.text('Contraer menú'), findsOneWidget);
  });
}
