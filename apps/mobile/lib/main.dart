import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference.dart';
import 'features/auth/application/auth_controller.dart';

void main() {
  // Nombres de meses y días en español (cuaderno de campo: "18 sep", "Hoy").
  // Sin esto, cualquier formato con nombre de mes revienta en ejecución.
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es_ES';
  initializeDateFormatting('es_ES');

  runApp(const ProviderScope(child: IotPlatformApp()));
}

class IotPlatformApp extends ConsumerStatefulWidget {
  const IotPlatformApp({super.key});

  @override
  ConsumerState<IotPlatformApp> createState() => _IotPlatformAppState();
}

class _IotPlatformAppState extends ConsumerState<IotPlatformApp> {
  @override
  void initState() {
    super.initState();
    // Intenta restaurar la sesión desde el refresh token persistido antes de
    // decidir a qué pantalla llevar al usuario (ARCHITECTURE.md §6).
    Future.microtask(() => ref.read(authControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final preference = ref.watch(themePreferenceProvider);
    // Aún no hay MediaQuery por encima de MaterialApp: el tamaño sale de la
    // propia ventana.
    final isPhone = isPhoneSized(MediaQueryData.fromView(View.of(context)).size);

    return MaterialApp.router(
      title: 'Plataforma IoT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: resolveThemeMode(preference, isPhone: isPhone),
      // La app es en español: los widgets de Material también (el selector de
      // fecha del cuaderno, sin ir más lejos).
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
