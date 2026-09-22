import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/campaigns_controller.dart';
import 'notebook_catalog_screen.dart';

/// Elegir del catálogo del cuaderno sin salir del formulario: la lista de lo
/// guardado y, al final, "Añadir…", que abre el alta y deja elegida la persona
/// o el equipo recién creado. Teclear el NIF y el ROPO en cada tratamiento era
/// justo lo que hacía impracticable el cuaderno completo.
class SelectorDePersona extends ConsumerWidget {
  const SelectorDePersona({
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.tipos = const [],
    this.ayuda,
    super.key,
  });

  final String etiqueta;
  final String? valor;
  final void Function(String? id) onCambio;

  /// Si se da, solo se ofrecen esos tipos (`own_staff`, `adviser`…).
  final List<String> tipos;
  final String? ayuda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasDelCuadernoProvider);

    return personas.when(
      loading: () => _Cargando(etiqueta: etiqueta),
      error: (_, __) => _NoDisponible(etiqueta: etiqueta),
      data: (lista) {
        final visibles =
            tipos.isEmpty ? lista : lista.where((p) => tipos.contains(p.kind)).toList();
        // El elegido puede estar dado de baja o ser de otro tipo: se deja en
        // la lista para no borrarlo sin querer al abrir el formulario.
        final elegido = visibles.any((p) => p.id == valor) ? valor : null;

        return DropdownButtonFormField<String>(
          initialValue: elegido,
          isExpanded: true,
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Sin indicar')),
            for (final persona in visibles)
              DropdownMenuItem(value: persona.id, child: Text(persona.displayName)),
            const DropdownMenuItem<String>(value: _nuevo, child: Text('Añadir persona…')),
          ],
          onChanged: (seleccion) async {
            if (seleccion != _nuevo) {
              onCambio(seleccion);
              return;
            }
            final creada = await editarPersona(context, ref);
            if (creada != null) onCambio(creada.id);
          },
        );
      },
    );
  }
}

class SelectorDeEquipo extends ConsumerWidget {
  const SelectorDeEquipo({
    required this.valor,
    required this.onCambio,
    this.etiqueta = 'Equipo de aplicación',
    super.key,
  });

  final String? valor;
  final void Function(String? id) onCambio;
  final String etiqueta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipos = ref.watch(equiposDelCuadernoProvider);

    return equipos.when(
      loading: () => _Cargando(etiqueta: etiqueta),
      error: (_, __) => _NoDisponible(etiqueta: etiqueta),
      data: (lista) {
        final elegido = lista.any((e) => e.id == valor) ? valor : null;
        return DropdownButtonFormField<String>(
          initialValue: elegido,
          isExpanded: true,
          decoration: InputDecoration(labelText: etiqueta),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Sin indicar')),
            for (final equipo in lista)
              DropdownMenuItem(value: equipo.id, child: Text(equipo.displayName)),
            const DropdownMenuItem<String>(value: _nuevo, child: Text('Añadir equipo…')),
          ],
          onChanged: (seleccion) async {
            if (seleccion != _nuevo) {
              onCambio(seleccion);
              return;
            }
            final creado = await editarEquipo(context, ref);
            if (creado != null) onCambio(creado.id);
          },
        );
      },
    );
  }
}

/// Valor reservado de la última opción; no es un identificador válido.
const _nuevo = '__nuevo__';

class _Cargando extends StatelessWidget {
  const _Cargando({required this.etiqueta});

  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: etiqueta),
      child: Text('Cargando…', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// Si el catálogo no carga, el formulario sigue siendo usable: se guarda todo
/// lo demás y esto se rellena luego.
class _NoDisponible extends StatelessWidget {
  const _NoDisponible({required this.etiqueta});

  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        helperText: 'No se pudo cargar la lista; puedes añadirlo después',
      ),
      child: Text(
        'Sin indicar',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
