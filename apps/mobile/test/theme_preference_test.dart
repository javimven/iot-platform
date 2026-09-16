import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/core/theme/theme_preference.dart';

/// Apariencia (BACKLOG.md #49, mejora G): en automático, claro en el móvil
/// aunque el sistema esté en oscuro; en pantallas grandes, el del sistema.
class _MemoryStore implements PreferenceStore {
  _MemoryStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _BrokenStore implements PreferenceStore {
  @override
  Future<String?> read(String key) => Future.error(Exception('sin almacenamiento'));

  @override
  Future<void> write(String key, String value) => Future.error(Exception('sin almacenamiento'));
}

void main() {
  group('resolveThemeMode', () {
    test('automático: claro en el móvil, el del sistema en pantallas grandes', () {
      expect(resolveThemeMode(ThemePreference.auto, isPhone: true), ThemeMode.light);
      expect(resolveThemeMode(ThemePreference.auto, isPhone: false), ThemeMode.system);
    });

    test('una elección explícita manda en cualquier pantalla', () {
      for (final isPhone in [true, false]) {
        expect(resolveThemeMode(ThemePreference.dark, isPhone: isPhone), ThemeMode.dark);
        expect(resolveThemeMode(ThemePreference.light, isPhone: isPhone), ThemeMode.light);
      }
    });
  });

  test('isPhoneSized mira el lado corto, así que girar el móvil no cambia nada', () {
    expect(isPhoneSized(const Size(390, 844)), isTrue);
    expect(isPhoneSized(const Size(844, 390)), isTrue);
    expect(isPhoneSized(const Size(1280, 800)), isFalse);
  });

  ProviderContainer container(PreferenceStore store) {
    final c = ProviderContainer(overrides: [preferenceStoreProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    return c;
  }

  test('recupera la preferencia guardada y guarda la nueva', () async {
    final store = _MemoryStore({ThemePreferenceController.storageKey: 'dark'});
    final c = container(store);
    expect(c.read(themePreferenceProvider), ThemePreference.auto); // antes de cargar
    await Future<void>.delayed(Duration.zero);
    expect(c.read(themePreferenceProvider), ThemePreference.dark);

    await c.read(themePreferenceProvider.notifier).set(ThemePreference.light);
    expect(c.read(themePreferenceProvider), ThemePreference.light);
    expect(store.values[ThemePreferenceController.storageKey], 'light');
  });

  test('sin almacenamiento disponible sigue funcionando en la sesión', () async {
    final c = container(_BrokenStore());
    await Future<void>.delayed(Duration.zero);
    expect(c.read(themePreferenceProvider), ThemePreference.auto);
    await c.read(themePreferenceProvider.notifier).set(ThemePreference.dark);
    expect(c.read(themePreferenceProvider), ThemePreference.dark);
  });
}
