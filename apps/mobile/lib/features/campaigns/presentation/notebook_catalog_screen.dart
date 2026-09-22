import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/notebook_models.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;
import 'selector_de_fecha.dart';

const _tiposDePersona = {
  'own_staff': 'Personal propio',
  'service_company': 'Empresa de servicios',
  'adviser': 'Asesor',
};

/// Personas y equipos del cuaderno (fase 5 del #60). Se dan de alta una vez y
/// se eligen después al registrar un tratamiento, en vez de teclear el NIF y
/// el número de ROPO en cada uno.
class NotebookCatalogScreen extends ConsumerWidget {
  const NotebookCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosDeCampanaProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Personas y equipos'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Personas'), Tab(text: 'Equipos')],
          ),
        ),
        body: TabBarView(
          children: [
            _ListaDePersonas(puedeEditar: permisos.puedeCrear),
            _ListaDeEquipos(puedeEditar: permisos.puedeCrear),
          ],
        ),
      ),
    );
  }
}

class _ListaDePersonas extends ConsumerWidget {
  const _ListaDePersonas({required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasDelCuadernoProvider);

    return personas.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudieron cargar las personas',
        detalle: mensajeDeError(error),
      ),
      data: (lista) => _Lista(
        vacio: const MensajeDeCampanas(
          icono: Icons.badge_outlined,
          titulo: 'Todavía no hay personas',
          detalle: 'Guarda aquí a quien hace los tratamientos y a tu asesor, con su NIF y su '
              'número de ROPO. Después se eligen de una lista.',
        ),
        elementos: lista.length,
        puedeEditar: puedeEditar,
        etiquetaDeAlta: 'Añadir persona',
        onAlta: () => editarPersona(context, ref),
        itemBuilder: (context, i) => AppCard(
          padding: const EdgeInsets.all(12),
          onTap: puedeEditar ? () => editarPersona(context, ref, persona: lista[i]) : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lista[i].displayName, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _tiposDePersona[lista[i].kind] ?? lista[i].kind,
                        if (lista[i].nif != null) lista[i].nif!,
                        if (lista[i].ropoNumber != null) 'ROPO ${lista[i].ropoNumber}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (puedeEditar) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListaDeEquipos extends ConsumerWidget {
  const _ListaDeEquipos({required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipos = ref.watch(equiposDelCuadernoProvider);

    return equipos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudieron cargar los equipos',
        detalle: mensajeDeError(error),
      ),
      data: (lista) => _Lista(
        vacio: const MensajeDeCampanas(
          icono: Icons.agriculture_outlined,
          titulo: 'Todavía no hay equipos',
          detalle: 'El atomizador, la cuba, la mochila… con su marca y, si lo tiene, su '
              'número de ROMA y la última inspección.',
        ),
        elementos: lista.length,
        puedeEditar: puedeEditar,
        etiquetaDeAlta: 'Añadir equipo',
        onAlta: () => editarEquipo(context, ref),
        itemBuilder: (context, i) => AppCard(
          padding: const EdgeInsets.all(12),
          onTap: puedeEditar ? () => editarEquipo(context, ref, equipo: lista[i]) : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lista[i].displayName, style: Theme.of(context).textTheme.bodyLarge),
                    if (lista[i].romaNumber != null || lista[i].lastInspectionOn != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (lista[i].romaNumber != null) 'ROMA ${lista[i].romaNumber}',
                          if (lista[i].lastInspectionOn != null)
                            'Inspección: ${fechaCorta(lista[i].lastInspectionOn!)}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (puedeEditar) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista con su botón de alta arriba, igual para personas y equipos.
class _Lista extends StatelessWidget {
  const _Lista({
    required this.vacio,
    required this.elementos,
    required this.puedeEditar,
    required this.etiquetaDeAlta,
    required this.onAlta,
    required this.itemBuilder,
  });

  final Widget vacio;
  final int elementos;
  final bool puedeEditar;
  final String etiquetaDeAlta;
  final VoidCallback onAlta;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (elementos == 0) {
      return Column(
        children: [
          Expanded(child: vacio),
          if (puedeEditar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: AppButton(
                label: etiquetaDeAlta,
                icon: Icons.add,
                expand: true,
                onPressed: onAlta,
              ),
            ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: elementos + (puedeEditar ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == elementos) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppButton(
              label: etiquetaDeAlta,
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: onAlta,
            ),
          );
        }
        return itemBuilder(context, i);
      },
    );
  }
}

/// Alta o cambio de una persona. Devuelve la persona guardada, para poder
/// elegirla directamente cuando se da de alta desde un tratamiento.
Future<PersonaCuaderno?> editarPersona(
  BuildContext context,
  WidgetRef ref, {
  PersonaCuaderno? persona,
}) {
  return showModalBottomSheet<PersonaCuaderno>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FormularioDePersona(persona: persona),
  );
}

Future<EquipoCuaderno?> editarEquipo(
  BuildContext context,
  WidgetRef ref, {
  EquipoCuaderno? equipo,
}) {
  return showModalBottomSheet<EquipoCuaderno>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FormularioDeEquipo(equipo: equipo),
  );
}

class _FormularioDePersona extends ConsumerStatefulWidget {
  const _FormularioDePersona({this.persona});

  final PersonaCuaderno? persona;

  @override
  ConsumerState<_FormularioDePersona> createState() => _FormularioDePersonaState();
}

class _FormularioDePersonaState extends ConsumerState<_FormularioDePersona> {
  late String _tipo = widget.persona?.kind ?? 'own_staff';
  late final _nombre = TextEditingController(text: widget.persona?.firstName ?? '');
  late final _apellido1 = TextEditingController(text: widget.persona?.surname1 ?? '');
  late final _apellido2 = TextEditingController(text: widget.persona?.surname2 ?? '');
  late final _empresa = TextEditingController(text: widget.persona?.companyName ?? '');
  late final _nif = TextEditingController(text: widget.persona?.nif ?? '');
  late final _ropo = TextEditingController(text: widget.persona?.ropoNumber ?? '');
  late final _carne = TextEditingController(text: widget.persona?.ropoCardType ?? '');
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nombre, _apellido1, _apellido2, _empresa, _nif, _ropo, _carne]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty && _empresa.text.trim().isEmpty) {
      setState(() => _error = 'Pon al menos el nombre o la razón social.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final cuerpo = PersonaCuaderno.cuerpo(
      kind: _tipo,
      firstName: _nombre.text,
      surname1: _apellido1.text,
      surname2: _apellido2.text,
      companyName: _empresa.text,
      nif: _nif.text,
      ropoNumber: _ropo.text,
      ropoCardType: _carne.text,
    );
    final navegador = Navigator.of(context);
    try {
      final api = ref.read(campaignsApiProvider);
      final guardada = widget.persona == null
          ? await api.crearPersona(cuerpo)
          : await api.cambiarPersona(widget.persona!.id, cuerpo);
      refrescarCatalogos(ref);
      navegador.pop(guardada);
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  Future<void> _borrar() async {
    final navegador = Navigator.of(context);
    setState(() => _guardando = true);
    try {
      await ref.read(campaignsApiProvider).borrarPersona(widget.persona!.id);
      refrescarCatalogos(ref);
      navegador.pop();
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _HojaDeFormulario(
      titulo: widget.persona == null ? 'Nueva persona' : 'Cambiar persona',
      guardando: _guardando,
      error: _error,
      onGuardar: _guardar,
      onBorrar: widget.persona == null ? null : _borrar,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [
            for (final entrada in _tiposDePersona.entries)
              DropdownMenuItem(value: entrada.key, child: Text(entrada.value)),
          ],
          onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
        ),
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        TextField(
          controller: _apellido1,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Primer apellido'),
        ),
        TextField(
          controller: _apellido2,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Segundo apellido'),
        ),
        TextField(
          controller: _empresa,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Razón social',
            helperText: 'Si es una empresa de servicios o un despacho de asesoría',
          ),
        ),
        TextField(
          controller: _nif,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'NIF'),
        ),
        TextField(
          controller: _ropo,
          decoration: const InputDecoration(
            labelText: 'Número de ROPO',
            helperText: 'Registro Oficial de Productores y Operadores',
          ),
        ),
        TextField(
          controller: _carne,
          decoration: const InputDecoration(labelText: 'Tipo de carné'),
        ),
      ],
    );
  }
}

class _FormularioDeEquipo extends ConsumerStatefulWidget {
  const _FormularioDeEquipo({this.equipo});

  final EquipoCuaderno? equipo;

  @override
  ConsumerState<_FormularioDeEquipo> createState() => _FormularioDeEquipoState();
}

class _FormularioDeEquipoState extends ConsumerState<_FormularioDeEquipo> {
  late final _descripcion = TextEditingController(text: widget.equipo?.description ?? '');
  late final _marca = TextEditingController(text: widget.equipo?.brand ?? '');
  late final _modelo = TextEditingController(text: widget.equipo?.model ?? '');
  late final _roma = TextEditingController(text: widget.equipo?.romaNumber ?? '');
  late DateTime? _inspeccion = widget.equipo?.lastInspectionOn;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_descripcion, _marca, _modelo, _roma]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_descripcion.text.trim().isEmpty) {
      setState(() => _error = 'Pon al menos qué equipo es.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final cuerpo = EquipoCuaderno.cuerpo(
      description: _descripcion.text,
      brand: _marca.text,
      model: _modelo.text,
      romaNumber: _roma.text,
      lastInspectionOn: _inspeccion,
    );
    final navegador = Navigator.of(context);
    try {
      final api = ref.read(campaignsApiProvider);
      final guardado = widget.equipo == null
          ? await api.crearEquipo(cuerpo)
          : await api.cambiarEquipo(widget.equipo!.id, cuerpo);
      refrescarCatalogos(ref);
      navegador.pop(guardado);
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  Future<void> _borrar() async {
    final navegador = Navigator.of(context);
    setState(() => _guardando = true);
    try {
      await ref.read(campaignsApiProvider).borrarEquipo(widget.equipo!.id);
      refrescarCatalogos(ref);
      navegador.pop();
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _HojaDeFormulario(
      titulo: widget.equipo == null ? 'Nuevo equipo' : 'Cambiar equipo',
      guardando: _guardando,
      error: _error,
      onGuardar: _guardar,
      onBorrar: widget.equipo == null ? null : _borrar,
      campos: [
        TextField(
          controller: _descripcion,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Qué equipo es',
            hintText: 'Atomizador, cuba, mochila…',
          ),
        ),
        TextField(
          controller: _marca,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Marca'),
        ),
        TextField(
          controller: _modelo,
          decoration: const InputDecoration(labelText: 'Modelo'),
        ),
        TextField(
          controller: _roma,
          decoration: const InputDecoration(
            labelText: 'Número de ROMA',
            helperText: 'Registro Oficial de Maquinaria Agrícola',
          ),
        ),
        SelectorDeFecha(
          etiqueta: 'Última inspección',
          valor: _inspeccion,
          onCambio: (fecha) => setState(() => _inspeccion = fecha),
          onQuitar: () => setState(() => _inspeccion = null),
        ),
      ],
    );
  }
}

/// La hoja de un formulario del catálogo: título, campos, guardar y borrar.
class _HojaDeFormulario extends StatelessWidget {
  const _HojaDeFormulario({
    required this.titulo,
    required this.campos,
    required this.guardando,
    required this.onGuardar,
    this.onBorrar,
    this.error,
  });

  final String titulo;
  final List<Widget> campos;
  final bool guardando;
  final VoidCallback onGuardar;
  final VoidCallback? onBorrar;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(titulo, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final campo in campos)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: campo),
          if (error != null) ...[
            Text(error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          AppButton(
            label: 'Guardar',
            expand: true,
            loading: guardando,
            onPressed: guardando ? null : onGuardar,
          ),
          if (onBorrar != null) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Dar de baja',
              variant: AppButtonVariant.danger,
              expand: true,
              onPressed: guardando ? null : onBorrar,
            ),
            const SizedBox(height: 8),
            Text(
              'Dejará de salir en las listas. Lo ya registrado no cambia: cada tratamiento '
              'guarda su propia copia.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
