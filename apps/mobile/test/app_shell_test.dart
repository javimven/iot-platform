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

/// Navegación (BACKLOG.md #49, mejora A): barra inferior con Estaciones,
/// Alertas, Gráficos y "Más", en cualquier tamaño de pantalla.
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

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  String location = '/stations',
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          for (final path in _branches)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => Scaffold(body: Text('Pantalla $path')),
                  routes: [
                    GoRoute(path: ':id', builder: (context, state) => const Scaffold(body: Text('Detalle'))),
                  ],
                ),
              ],
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
      child: MaterialApp.router(theme: ThemeData(platform: platform), routerConfig: router),
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

  testWidgets('un móvil girado sigue con la barra inferior, no con el menú lateral', (tester) async {
    await _pumpShell(tester, const Size(844, 390));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Contraer menú'), findsNothing);
  });

  testWidgets('E: en la pantalla de una estación con el móvil girado no hay barra inferior', (tester) async {
    await _pumpShell(tester, const Size(844, 390), location: '/stations/gw-1');
    expect(find.text('Detalle'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('en el ordenador: menú lateral con todas las secciones y la cuenta, sin barra inferior', (tester) async {
    // Decisión del usuario (2026-09-21): en el ordenador hay sitio para los
    // menús, no tiene sentido esconderlos tras «Más» (BACKLOG.md #56).
    await _pumpShell(tester, const Size(1280, 800));

    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['Estaciones', 'Alertas', 'Gráficos personalizados', 'Informes', 'Infraestructura']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Sesiones activas'), findsOneWidget);
    expect(find.text('Apariencia'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.text('Infraestructura'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla /infrastructure'), findsOneWidget);
  });

  testWidgets('en el ordenador los datos ocupan todo el ancho que deja el menú', (tester) async {
    // Decisión del usuario (2026-09-21): se quitó la columna centrada de 900
    // px — «que la parte de datos se adapte al ancho de la pantalla siempre».
    await _pumpShell(tester, const Size(1600, 900));

    expect(tester.getSize(find.byType(StatefulNavigationShell)).width, 1600 - 240); // todo menos el menú
  });

  group('ordenador con la ventana pequeña', () {
    testWidgets('sigue siendo escritorio, no un móvil tumbado', (tester) async {
      // El fallo que corrige (2026-09-21): al encoger la ventana, la web de
      // ordenador pasaba a barra inferior porque las medidas se parecían a las
      // de un teléfono girado.
      await _pumpShell(tester, const Size(900, 520), platform: TargetPlatform.windows);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byIcon(Icons.sensors_outlined), findsOneWidget);
    });

    testWidgets('el menú se encoge a iconos y la cuenta cabe en uno solo', (tester) async {
      await _pumpShell(tester, const Size(900, 520), platform: TargetPlatform.windows);

      // Sin etiquetas: solo iconos con su aviso emergente.
      expect(find.text('Estaciones'), findsNothing);
      expect(find.text('Cerrar sesión'), findsNothing);
      expect(tester.getSize(find.byType(StatefulNavigationShell)).width, 900 - anchoMenuIconos);

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      for (final label in ['Sesiones activas', 'Apariencia', 'Cerrar sesión']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('con la ventana ancha vuelven las etiquetas', (tester) async {
      await _pumpShell(tester, const Size(1400, 900), platform: TargetPlatform.windows);
      expect(find.text('Estaciones'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('en la pantalla de una estación no se va a la gráfica a pantalla completa', (tester) async {
      await _pumpShell(tester, const Size(900, 520), location: '/stations/gw-1', platform: TargetPlatform.windows);
      expect(find.byIcon(Icons.sensors_outlined), findsOneWidget); // el menú sigue ahí
    });
  });

  test('la disposición depende de la plataforma, no solo del tamaño', () {
    const ventanaPequena = Size(900, 520);
    const movilGirado = Size(844, 390);

    expect(usaMenuLateral(ventanaPequena, platform: TargetPlatform.windows), isTrue);
    expect(isPhoneLandscape(ventanaPequena, platform: TargetPlatform.windows), isFalse);
    expect(menuLateralCompleto(ventanaPequena), isFalse);

    expect(usaMenuLateral(movilGirado, platform: TargetPlatform.iOS), isFalse);
    expect(isPhoneLandscape(movilGirado, platform: TargetPlatform.iOS), isTrue);

    // Una tableta ancha se queda como estaba: menú lateral.
    expect(usaMenuLateral(const Size(1024, 768), platform: TargetPlatform.iOS), isTrue);
  });
}
