import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Apariencia elegida por el usuario. `auto` es el valor por defecto: tema
/// claro en el móvil aunque el sistema esté en oscuro, porque se usa en campo
/// y a pleno sol se lee mejor; en pantallas grandes, el del sistema.
enum ThemePreference { auto, light, dark }

extension ThemePreferenceLabel on ThemePreference {
  String get label => switch (this) {
        ThemePreference.auto => 'Automático',
        ThemePreference.light => 'Claro',
        ThemePreference.dark => 'Oscuro',
      };
}

/// Un teléfono, a efectos de tema: el lado corto de la ventana por debajo de
/// 600 px (el mismo corte que usa Material para distinguir móvil de tableta).
bool isPhoneSized(Size size) => size.shortestSide < 600;

ThemeMode resolveThemeMode(ThemePreference preference, {required bool isPhone}) => switch (preference) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.auto => isPhone ? ThemeMode.light : ThemeMode.system,
    };

/// Dónde se guarda la preferencia entre sesiones. Interfaz propia para poder
/// probar el controlador sin almacenamiento real.
abstract class PreferenceStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecurePreferenceStore implements PreferenceStore {
  SecurePreferenceStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

final preferenceStoreProvider = Provider<PreferenceStore>((ref) => SecurePreferenceStore());

class ThemePreferenceController extends StateNotifier<ThemePreference> {
  ThemePreferenceController(this._store) : super(ThemePreference.auto) {
    _load();
  }

  static const storageKey = 'theme_preference';
  final PreferenceStore _store;

  Future<void> _load() async {
    try {
      final saved = await _store.read(storageKey);
      final match = ThemePreference.values.where((p) => p.name == saved);
      if (match.isNotEmpty && mounted) state = match.first;
    } catch (_) {
      // Sin almacenamiento disponible (p. ej. navegador en modo privado): se
      // queda en automático, que es un valor válido.
    }
  }

  Future<void> set(ThemePreference preference) async {
    state = preference;
    try {
      await _store.write(storageKey, preference.name);
    } catch (_) {
      // Se aplica igualmente en esta sesión aunque no se pueda guardar.
    }
  }
}

final themePreferenceProvider = StateNotifierProvider<ThemePreferenceController, ThemePreference>(
  (ref) => ThemePreferenceController(ref.watch(preferenceStoreProvider)),
);

/// Selector de apariencia, compartido por el menú "Más" del móvil y el menú
/// de perfil del escritorio.
class ThemePreferenceSelector extends ConsumerWidget {
  const ThemePreferenceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themePreferenceProvider);
    return SegmentedButton<ThemePreference>(
      segments: [
        for (final p in ThemePreference.values) ButtonSegment(value: p, label: Text(p.label)),
      ],
      selected: {preference},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => ref.read(themePreferenceProvider.notifier).set(selection.first),
    );
  }
}
