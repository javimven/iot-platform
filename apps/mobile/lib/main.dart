import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference.dart';
import 'features/auth/application/auth_controller.dart';

void main() {
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
      routerConfig: router,
    );
  }
}
