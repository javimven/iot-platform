import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../installations/application/installations_controller.dart';
import '../../parcels/application/parcels_controller.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;
import 'selector_de_fecha.dart';

/// Alta de una campaña (BACKLOG.md #60). Dos pasos: qué se quiere llevar
/// (seguimiento sencillo o cuaderno completo) y los cuatro datos que hacen
/// falta. El objetivo es crearla en menos de un minuto.
class NewCampaignScreen extends ConsumerStatefulWidget {
  const NewCampaignScreen({super.key});

  @override
  ConsumerState<NewCampaignScreen> createState() => _NewCampaignScreenState();
}

class _NewCampaignScreenState extends ConsumerState<NewCampaignScreen> {
  String? _modo;
  String? _fincaId;
  final _parcelas = <String>{};
  CultivoCatalogo? _cultivo;
  final _cultivoEscrito = TextEditingController();
  final _variedad = TextEditingController();
  final _nombre = TextEditingController();
  final _notas = TextEditingController();
  DateTime _inicio = DateTime.now();
  DateTime? _finPrevista;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _cultivoEscrito.dispose();
    _variedad.dispose();
    _nombre.dispose();
    _notas.dispose();
    super.dispose();
  }

  /// Igual que en el formulario de actividades: los trozos de la pantalla
  /// avisan por aquí en vez de llamar al `setState` de otra clase.
  void actualizar(VoidCallback cambio) => setState(cambio);

  bool get _listo =>
      _fincaId != null &&
      _parcelas.isNotEmpty &&
      (_cultivo != null || _cultivoEscrito.text.trim().isNotEmpty) &&
      !_guardando;

  Future<void> _crear() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final campana = await ref.read(campaignsApiProvider).crear(
            _fincaId!,
            NuevaCampana(
              managementMode: _modo!,
              startDate: _inicio,
              expectedEndDate: _finPrevista,
              parcelIds: _parcelas.toList(),
              cropId: _cultivo?.id,
              cropName: _cultivo == null ? _cultivoEscrito.text : null,
              variety: _variedad.text,
              name: _nombre.text,
              notes: _notas.text,
            ),
          );
      ref.invalidate(campanasProvider);
      if (mounted) {
        context.pushReplacement('/campaigns/${campana.id}');
      }
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_modo == null ? 'Nueva campaña' : 'Datos de la campaña')),
      body: _modo == null
          ? _EleccionDeModo(onElegido: (modo) => setState(() => _modo = modo))
          : _Formulario(estado: this),
    );
  }
}

class _EleccionDeModo extends StatelessWidget {
  const _EleccionDeModo({required this.onElegido});

  final void Function(String modo) onElegido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget opcion({
      required String modo,
      required IconData icono,
      required String titulo,
      required String detalle,
    }) =>
        AppCard(
          onTap: () => onElegido(modo),
          child: Row(
            children: [
              Icon(icono, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(detalle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('¿Qué quieres llevar?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        opcion(
          modo: 'simple',
          icono: Icons.eco_outlined,
          titulo: 'Campaña sencilla',
          detalle:
              'Seguimiento rápido del cultivo. Podrás convertirla en cuaderno completo cuando quieras.',
        ),
        const SizedBox(height: 12),
        opcion(
          modo: 'complete',
          icono: Icons.menu_book_outlined,
          titulo: 'Cuaderno de campo completo',
          detalle: 'Registra toda la información agronómica y documental de la campaña.',
        ),
      ],
    );
  }
}

class _Formulario extends ConsumerWidget {
  const _Formulario({required this.estado});

  final _NewCampaignScreenState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fincas = ref.watch(installationsListProvider);

    return fincas.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudieron cargar las fincas',
        detalle: mensajeDeError(error),
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const MensajeDeCampanas(
            icono: Icons.agriculture_outlined,
            titulo: 'Todavía no hay fincas',
            detalle: 'Crea una finca en Infraestructura para poder llevar campañas.',
          );
        }
        final fincaId = estado._fincaId ??= lista.first.id;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (lista.length > 1)
              DropdownButtonFormField<String>(
                initialValue: fincaId,
                decoration: const InputDecoration(labelText: 'Finca'),
                items: [
                  for (final finca in lista)
                    DropdownMenuItem(value: finca.id, child: Text(finca.name)),
                ],
                onChanged: (id) => estado.actualizar(() {
                  estado._fincaId = id;
                  estado._parcelas.clear();
                }),
              ),
            const SizedBox(height: 16),
            Text('Parcelas', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            _Parcelas(estado: estado, installationId: fincaId),
            const SizedBox(height: 16),
            _Cultivo(estado: estado),
            const SizedBox(height: 12),
            TextField(
              controller: estado._variedad,
              decoration: const InputDecoration(labelText: 'Variedad (opcional)', hintText: 'Hass'),
              onChanged: (_) => estado.actualizar(() {}),
            ),
            const SizedBox(height: 12),
            SelectorDeFecha(
              etiqueta: 'Fecha de inicio',
              valor: estado._inicio,
              onCambio: (fecha) => estado.actualizar(() => estado._inicio = fecha),
            ),
            const SizedBox(height: 12),
            SelectorDeFecha(
              etiqueta: 'Fin previsto (opcional)',
              valor: estado._finPrevista,
              primeraFecha: estado._inicio,
              onCambio: (fecha) => estado.actualizar(() => estado._finPrevista = fecha),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: estado._nombre,
              decoration: InputDecoration(
                labelText: 'Nombre (opcional)',
                hintText: _nombreAutomatico(estado),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: estado._notas,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            if (estado._error != null) ...[
              const SizedBox(height: 12),
              Text(
                estado._error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: estado._modo == 'complete' ? 'Crear cuaderno' : 'Crear campaña',
              expand: true,
              loading: estado._guardando,
              onPressed: estado._listo ? estado._crear : null,
            ),
          ],
        );
      },
    );
  }
}

/// Lo mismo que hace el backend si no se pone nombre: así se ve antes.
String _nombreAutomatico(_NewCampaignScreenState estado) {
  final cultivo = estado._cultivo?.name ?? estado._cultivoEscrito.text.trim();
  if (cultivo.isEmpty) return 'Aguacate Hass · 2026';
  final variedad = estado._variedad.text.trim();
  final anyoFin = estado._finPrevista?.year;
  final anyos = anyoFin != null && anyoFin > estado._inicio.year
      ? '${estado._inicio.year}/${anyoFin.toString().substring(2)}'
      : '${estado._inicio.year}';
  return '$cultivo${variedad.isEmpty ? '' : ' $variedad'} · $anyos';
}

class _Parcelas extends ConsumerWidget {
  const _Parcelas({required this.estado, required this.installationId});

  final _NewCampaignScreenState estado;
  final String installationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelas = ref.watch(parcelasDeFincaProvider(installationId));

    return parcelas.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(mensajeDeError(error)),
      data: (lista) {
        if (lista.isEmpty) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Esta finca todavía no tiene parcelas. Dibuja el contorno de una en el mapa '
                  'y vuelve: la campaña se lleva sobre parcelas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Dibujar parcela',
                  icon: Icons.map_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () async {
                    await context.push('/installations/$installationId/parcels/new');
                    ref.invalidate(parcelasDeFincaProvider(installationId));
                  },
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final parcela in lista)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: estado._parcelas.contains(parcela.id),
                title: Text(parcela.name),
                subtitle: Text(superficie(parcela.areaHa)),
                onChanged: (marcada) => estado.actualizar(() {
                  if (marcada ?? false) {
                    estado._parcelas.add(parcela.id);
                  } else {
                    estado._parcelas.remove(parcela.id);
                  }
                }),
              ),
          ],
        );
      },
    );
  }
}

/// Cultivo del catálogo, o escrito a mano si no está. Se busca sin tildes:
/// "platano" encuentra "Plátano".
class _Cultivo extends ConsumerWidget {
  const _Cultivo({required this.estado});

  final _NewCampaignScreenState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cultivos = ref.watch(cultivosProvider).valueOrNull ?? const <CultivoCatalogo>[];

    return Autocomplete<CultivoCatalogo>(
      displayStringForOption: (cultivo) => cultivo.name,
      initialValue: TextEditingValue(text: estado._cultivoEscrito.text),
      optionsBuilder: (valor) {
        final texto = sinTildes(valor.text);
        if (texto.isEmpty) return cultivos;
        return cultivos.where((c) => sinTildes(c.name).contains(texto));
      },
      onSelected: (cultivo) => estado.actualizar(() {
        estado._cultivo = cultivo;
        estado._cultivoEscrito.text = cultivo.name;
      }),
      fieldViewBuilder: (context, controlador, foco, onSubmit) => TextField(
        controller: controlador,
        focusNode: foco,
        decoration: const InputDecoration(
          labelText: 'Cultivo',
          hintText: 'Aguacate, tomate, olivo…',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (texto) => estado.actualizar(() {
          // Lo escrito manda: si no coincide con el catálogo, se guarda tal cual.
          estado._cultivoEscrito.text = texto;
          estado._cultivo = null;
        }),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

/// Minúsculas y sin tildes, para buscar como se escribe con prisa.
String sinTildes(String texto) {
  const con = 'áéíóúüàèìòùäëïöñç';
  const sin = 'aeiouuaeiouaeionc';
  var resultado = texto.toLowerCase();
  for (var i = 0; i < con.length; i++) {
    resultado = resultado.replaceAll(con[i], sin[i]);
  }
  return resultado;
}
