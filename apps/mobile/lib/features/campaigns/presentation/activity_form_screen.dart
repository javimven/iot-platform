import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/activity_models.dart';
import '../data/campaign_models.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;
import 'selector_de_fecha.dart';

enum ModoDeFormulario { nueva, repetir, editar }

/// Registrar (o repetir, o corregir) una actividad. Un solo formulario para
/// todos los tipos: arriba lo imprescindible, y lo del cuaderno completo
/// detrás de "Más detalles" —desplegado ya si la campaña es un cuaderno
/// completo— (ADR-0013).
class ActivityFormScreen extends ConsumerStatefulWidget {
  const ActivityFormScreen({
    required this.campaignId,
    required this.tipo,
    this.base,
    this.modo = ModoDeFormulario.nueva,
    super.key,
  });

  final String campaignId;
  final String tipo;

  /// La actividad de la que se parte al repetir o corregir.
  final Actividad? base;
  final ModoDeFormulario modo;

  @override
  ConsumerState<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends ConsumerState<ActivityFormScreen> {
  final _textos = <String, TextEditingController>{};
  final _detalle = <String, dynamic>{};
  final _productos = <Map<String, dynamic>>[];
  final _destinos = <String>{};
  late DateTime _inicio;
  DateTime? _fin;
  String? _hora;
  bool _variosDias = false;
  bool _guardando = false;
  bool _inicializado = false;
  String? _error;

  String? get _claveDetalle => claveDelDetalle(widget.tipo);

  /// Para que los trozos del formulario (que son widgets aparte, por
  /// legibilidad) puedan refrescar la pantalla sin tocar `setState`, que es
  /// de la propia clase.
  void actualizar(VoidCallback cambio) => setState(cambio);

  @override
  void initState() {
    super.initState();
    final base = widget.base;
    // Al repetir, la fecha es hoy: es lo único que casi siempre cambia.
    _inicio =
        widget.modo == ModoDeFormulario.editar && base != null ? base.startDate : DateTime.now();
    if (base != null && widget.modo == ModoDeFormulario.editar && base.esDeVariosDias) {
      _variosDias = true;
      _fin = base.endDate;
    }
    _hora = base?.startTime;
    if (base?.notes != null) _texto('notes').text = base!.notes!;
    if (base?.detalle != null) {
      for (final entrada in base!.detalle!.entries) {
        if (entrada.key == 'products') continue;
        if (entrada.value != null) _detalle[entrada.key] = entrada.value;
      }
      _productos.addAll(base.productos.map((p) => {...p}));
    }
    if (widget.tipo == 'phytosanitary' && _productos.isEmpty) {
      _productos.add(<String, dynamic>{});
    }
  }

  @override
  void dispose() {
    for (final controlador in _textos.values) {
      controlador.dispose();
    }
    super.dispose();
  }

  TextEditingController _texto(String clave) =>
      _textos.putIfAbsent(clave, () => TextEditingController(text: _valorInicial(clave)));

  String _valorInicial(String clave) {
    final valor = _detalle[clave];
    if (valor == null) return '';
    return valor is num ? cifraCorta(valor) : '$valor';
  }

  /// "1,5" y "1.5" son lo mismo aquí: en España se escribe con coma.
  double? _comoNumero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

  void _guardarTexto(String clave, String texto, {bool numero = false}) {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      _detalle.remove(clave);
      return;
    }
    if (numero) {
      final valor = _comoNumero(limpio);
      if (valor != null) _detalle[clave] = valor;
      return;
    }
    _detalle[clave] = limpio;
  }

  Map<String, dynamic> _cuerpo() {
    for (final entrada in _textos.entries) {
      if (entrada.key == 'notes') continue;
      _guardarTexto(entrada.key, entrada.value.text,
          numero: _clavesNumericas.contains(entrada.key));
    }
    final detalle = <String, dynamic>{..._detalle}..removeWhere((_, valor) => valor == null);
    if (widget.tipo == 'phytosanitary') {
      detalle['products'] = [
        for (final producto in _productos)
          if ((producto['productName'] as String?)?.trim().isNotEmpty ?? false)
            {...producto}..removeWhere((_, valor) => valor == null || valor == ''),
      ];
    }

    final notas = _texto('notes').text.trim();
    return {
      if (widget.modo != ModoDeFormulario.editar) 'type': widget.tipo,
      'startDate': escribirFecha(_inicio),
      if (_variosDias && _fin != null) 'endDate': escribirFecha(_fin!),
      if (_hora != null) 'startTime': _hora,
      if (notas.isNotEmpty) 'notes': notas,
      'targets': [
        for (final clave in _destinos)
          {'parcelId': clave.split('|')[1], 'cropUnitId': clave.split('|')[0]},
      ],
      if (_claveDetalle != null && detalle.isNotEmpty) _claveDetalle!: detalle,
      if (widget.modo == ModoDeFormulario.repetir) 'repeatedFromId': widget.base!.id,
    };
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final api = ref.read(campaignsApiProvider);
      if (widget.modo == ModoDeFormulario.editar) {
        await api.corregir(widget.campaignId, widget.base!.id, _cuerpo());
      } else {
        await api.registrar(widget.campaignId, _cuerpo());
      }
      refrescarCampana(ref, widget.campaignId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final campana = ref.watch(campanaProvider(widget.campaignId));
    final titulo = switch (widget.modo) {
      ModoDeFormulario.nueva => etiquetaDeTipo(widget.tipo),
      ModoDeFormulario.repetir => 'Repetir ${etiquetaDeTipo(widget.tipo).toLowerCase()}',
      ModoDeFormulario.editar => 'Corregir ${etiquetaDeTipo(widget.tipo).toLowerCase()}',
    };

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: campana.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MensajeDeCampanas(
          icono: Icons.cloud_off,
          titulo: 'No se pudo cargar la campaña',
          detalle: mensajeDeError(error),
        ),
        data: (datos) {
          _prepararDestinos(datos);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (widget.modo == ModoDeFormulario.repetir)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.copy_all_outlined, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Copiado de la actividad del ${fechaCorta(widget.base!.startDate)}. '
                            'Revisa los datos y guarda.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ..._camposDeFecha(),
              const SizedBox(height: 16),
              _Destinos(estado: this, campana: datos),
              const SizedBox(height: 16),
              ..._camposPrincipales(datos),
              const SizedBox(height: 8),
              _MasDetalles(estado: this, campana: datos),
              const SizedBox(height: 12),
              TextField(
                controller: _texto('notes'),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: widget.tipo == 'observation' ? 'Qué has visto' : 'Notas (opcional)',
                  hintText: widget.tipo == 'observation'
                      ? 'Las hojas de la zona norte empiezan a amarillear…'
                      : null,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(
                label: 'Guardar',
                expand: true,
                loading: _guardando,
                onPressed: _destinos.isEmpty ? null : _guardar,
              ),
            ],
          );
        },
      ),
    );
  }

  /// La primera vez: todas las parcelas de la campaña, o las de la actividad
  /// que se repite o se corrige. No pedir lo que ya se sabe.
  void _prepararDestinos(Campana campana) {
    if (_inicializado) return;
    _inicializado = true;
    final base = widget.base;
    if (base != null) {
      _destinos.addAll(base.targets.map((d) => '${d.cropUnitId}|${d.parcelId}'));
    } else {
      _destinos.addAll(campana.parcelas.map((p) => '${p.unidad.id}|${p.parcela.parcelId}'));
    }
  }

  List<Widget> _camposDeFecha() => [
        SelectorDeFecha(
          etiqueta: 'Fecha',
          valor: _inicio,
          ultimaFecha: DateTime.now(),
          onCambio: (fecha) => setState(() {
            _inicio = fecha;
            if (_fin != null && _fin!.isBefore(fecha)) _fin = fecha;
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Duró varios días'),
          subtitle: const Text('Por ejemplo, una fertirrigación de una quincena'),
          value: _variosDias,
          onChanged: (valor) => setState(() {
            _variosDias = valor;
            _fin ??= _inicio;
          }),
        ),
        if (_variosDias)
          SelectorDeFecha(
            etiqueta: 'Hasta',
            valor: _fin,
            primeraFecha: _inicio,
            onCambio: (fecha) => setState(() => _fin = fecha),
          ),
        if (widget.tipo == 'phytosanitary') ...[
          const SizedBox(height: 12),
          SelectorDeHora(valor: _hora, onCambio: (hora) => setState(() => _hora = hora)),
        ],
      ];

  /// Lo imprescindible de cada tipo: lo que se apunta en el campo.
  List<Widget> _camposPrincipales(Campana campana) {
    switch (widget.tipo) {
      case 'irrigation':
        return [
          _CampoConUnidad(
            estado: this,
            clave: 'amount',
            claveUnidad: 'amountUnit',
            etiqueta: 'Cantidad de agua (opcional)',
            unidades: unidadesDeRiego,
            unidadPorDefecto: 'm3_ha',
          ),
        ];
      case 'fertilization':
        return [
          _campoTexto('productName', 'Producto', hint: 'NPK 15-15-15, estiércol…'),
          const SizedBox(height: 12),
          _CampoConUnidad(
            estado: this,
            clave: 'dose',
            claveUnidad: 'doseUnit',
            etiqueta: 'Dosis',
            unidades: unidadesDeDosis,
            unidadPorDefecto: 'kg_ha',
          ),
        ];
      case 'phytosanitary':
        return [
          _Productos(estado: this),
          const SizedBox(height: 12),
          _campoTexto('problem', 'Plaga o problema', hint: 'Araña roja, mildiu…'),
        ];
      case 'harvest':
        return [
          _CampoConUnidad(
            estado: this,
            clave: 'quantity',
            claveUnidad: 'quantityUnit',
            etiqueta: 'Cantidad recolectada',
            unidades: unidadesDeCosecha,
            unidadPorDefecto: 'kg',
          ),
          const SizedBox(height: 12),
          _campoTexto(
            'product',
            'Producto (opcional)',
            hint: campana.cropUnits.isEmpty ? null : campana.cropUnits.first.nombre,
          ),
        ];
      case 'field_work':
        return [
          _campoOpciones('workType', 'Qué labor', tiposDeLabor),
        ];
      default:
        return const [];
    }
  }

  Widget _campoTexto(String clave, String etiqueta, {String? hint}) => TextField(
        controller: _texto(clave),
        decoration: InputDecoration(labelText: etiqueta, hintText: hint),
      );

  Widget _campoNumero(String clave, String etiqueta, {String? sufijo}) => TextField(
        controller: _texto(clave),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: etiqueta, suffixText: sufijo),
      );

  Widget _campoOpciones(String clave, String etiqueta, Map<String, String> opciones) =>
      DropdownButtonFormField<String>(
        initialValue: opciones.containsKey(_detalle[clave]) ? _detalle[clave] as String : null,
        decoration: InputDecoration(labelText: etiqueta),
        items: [
          for (final opcion in opciones.entries)
            DropdownMenuItem(value: opcion.key, child: Text(opcion.value)),
        ],
        onChanged: (valor) => setState(() => _detalle[clave] = valor),
      );

  Widget _campoSiNo(String clave, String etiqueta) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(etiqueta),
        value: _detalle[clave] == true,
        onChanged: (valor) => setState(() => _detalle[clave] = valor),
      );
}

/// Claves cuyo texto es un número.
const _clavesNumericas = {
  'amount',
  'dose',
  'quantity',
  'nPct',
  'p2o5Pct',
  'k2oPct',
  'organicMatterPct',
  'nitrateMgL',
  'p2o5MgL',
  'hours',
  'totalQuantity',
};

/// Un número con su unidad al lado: nunca uno sin la otra (el backend las
/// exige juntas, y una cifra suelta no significa nada).
class _CampoConUnidad extends StatelessWidget {
  const _CampoConUnidad({
    required this.estado,
    required this.clave,
    required this.claveUnidad,
    required this.etiqueta,
    required this.unidades,
    required this.unidadPorDefecto,
  });

  final _ActivityFormScreenState estado;
  final String clave;
  final String claveUnidad;
  final String etiqueta;
  final Map<String, String> unidades;
  final String unidadPorDefecto;

  @override
  Widget build(BuildContext context) {
    final unidad = estado._detalle[claveUnidad] as String? ?? unidadPorDefecto;
    estado._detalle[claveUnidad] = unidad;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: estado._campoNumero(clave, etiqueta)),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: unidad,
            decoration: const InputDecoration(labelText: 'Unidad'),
            items: [
              for (final opcion in unidades.entries)
                DropdownMenuItem(value: opcion.key, child: Text(opcion.value)),
            ],
            onChanged: (valor) => estado.actualizar(() => estado._detalle[claveUnidad] = valor),
          ),
        ),
      ],
    );
  }
}

/// Sobre qué parcelas. Vienen todas marcadas: lo normal es que la actividad
/// sea de toda la campaña, y desmarcar es más rápido que marcar.
class _Destinos extends StatelessWidget {
  const _Destinos({required this.estado, required this.campana});

  final _ActivityFormScreenState estado;
  final Campana campana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parcelas = campana.parcelas;
    final variosCultivos = campana.cropUnits.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parcelas', style: theme.textTheme.titleSmall),
        for (final p in parcelas)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: estado._destinos.contains('${p.unidad.id}|${p.parcela.parcelId}'),
            title: Text(
              variosCultivos ? '${p.parcela.name} · ${p.unidad.nombre}' : p.parcela.name,
            ),
            subtitle: Text(superficie(p.parcela.effectiveAreaHa)),
            onChanged: (marcada) => estado.actualizar(() {
              final clave = '${p.unidad.id}|${p.parcela.parcelId}';
              if (marcada ?? false) {
                estado._destinos.add(clave);
              } else {
                estado._destinos.remove(clave);
              }
            }),
          ),
        if (estado._destinos.isEmpty)
          Text(
            'Marca al menos una parcela.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
      ],
    );
  }
}

/// Los productos de un tratamiento: puede ser una mezcla de varios.
class _Productos extends StatelessWidget {
  const _Productos({required this.estado});

  final _ActivityFormScreenState estado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < estado._productos.length; i++) _producto(context, i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => estado.actualizar(() => estado._productos.add(<String, dynamic>{})),
            icon: const Icon(Icons.add),
            label: const Text('Añadir otro producto'),
          ),
        ),
      ],
    );
  }

  Widget _producto(BuildContext context, int indice) {
    final producto = estado._productos[indice];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: producto['productName'] as String? ?? '',
                  decoration: InputDecoration(
                    labelText: indice == 0 ? 'Producto' : 'Producto ${indice + 1}',
                    hintText: 'Nombre comercial',
                  ),
                  onChanged: (texto) => producto['productName'] = texto.trim(),
                ),
              ),
              if (estado._productos.length > 1)
                IconButton(
                  tooltip: 'Quitar este producto',
                  icon: const Icon(Icons.close),
                  onPressed: () => estado.actualizar(() => estado._productos.removeAt(indice)),
                ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: producto['dose'] == null ? '' : cifraCorta(producto['dose'] as num),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: 'Dosis'),
                  onChanged: (texto) {
                    final valor = estado._comoNumero(texto);
                    if (valor == null) {
                      producto.remove('dose');
                      producto.remove('doseUnit');
                    } else {
                      producto['dose'] = valor;
                      producto['doseUnit'] ??= 'kg_ha';
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: producto['doseUnit'] as String? ?? 'kg_ha',
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: [
                    for (final opcion in unidadesDeDosisFitosanitaria.entries)
                      DropdownMenuItem(value: opcion.key, child: Text(opcion.value)),
                  ],
                  onChanged: (valor) => estado.actualizar(() => producto['doseUnit'] = valor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lo del cuaderno completo. En una campaña sencilla va plegado: quien quiera
/// enriquecer el registro, lo abre; quien no, ni lo ve.
class _MasDetalles extends StatelessWidget {
  const _MasDetalles({required this.estado, required this.campana});

  final _ActivityFormScreenState estado;
  final Campana campana;

  @override
  Widget build(BuildContext context) {
    final campos = _campos(context);
    if (campos.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: campana.resumen.esCompleta,
        title: Text(campana.resumen.esCompleta ? 'Datos del cuaderno' : 'Más detalles'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final campo in campos)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: campo),
        ],
      ),
    );
  }

  List<Widget> _campos(BuildContext context) {
    switch (estado.widget.tipo) {
      case 'irrigation':
        return [
          estado._campoOpciones('system', 'Sistema de riego', sistemasDeRiego),
          estado._campoTexto('waterSource', 'Procedencia del agua'),
          estado._campoTexto('meterNumber', 'Número de contador'),
          estado._campoNumero('nitrateMgL', 'Nitratos del agua', sufijo: 'mg/l'),
          estado._campoNumero('p2o5MgL', 'P₂O₅ soluble del agua', sufijo: 'mg/l'),
        ];
      case 'fertilization':
        return [
          estado._campoOpciones('fertilizationType', 'Tipo de abonado', tiposDeFertilizacion),
          estado._campoOpciones('materialType', 'Material', materialesFertilizantes),
          estado._campoOpciones('applicationMethod', 'Forma de aplicación', metodosDeAplicacion),
          estado._campoNumero('nPct', 'Riqueza en N', sufijo: '%'),
          estado._campoNumero('p2o5Pct', 'Riqueza en P₂O₅', sufijo: '%'),
          estado._campoNumero('k2oPct', 'Riqueza en K₂O', sufijo: '%'),
          estado._campoNumero('organicMatterPct', 'Materia orgánica', sufijo: '%'),
          estado._campoTexto('supplierName', 'Empresa suministradora'),
          estado._campoTexto('supplierNif', 'NIF del suministrador'),
          estado._campoTexto('regferCode', 'Código REGFER'),
        ];
      case 'phytosanitary':
        return [
          estado._campoOpciones('problemCategory', 'Tipo de problema', categoriasDeProblema),
          estado._campoTexto('justification', 'Justificación de la actuación'),
          _EstadoFenologico(estado: estado),
          estado._campoOpciones('efficacy', 'Eficacia', eficacias),
          estado._campoSiNo('manualApplication', 'Aplicación manual'),
        ];
      case 'harvest':
        return [
          estado._campoTexto('lotCode', 'Lote'),
          estado._campoTexto('deliveryNote', 'Albarán o factura'),
          estado._campoTexto('customerName', 'Cliente'),
          estado._campoTexto('customerNif', 'NIF del cliente'),
          estado._campoTexto('destination', 'Destino'),
          estado._campoTexto('qualityGrade', 'Calidad o clasificación'),
        ];
      case 'field_work':
        return [
          estado._campoNumero('hours', 'Horas'),
          estado._campoTexto('machinery', 'Maquinaria'),
          estado._campoSiNo('pruningResiduesLeft', 'Restos de poda dejados en el suelo'),
          estado._campoSiNo('clearingResiduesLeft', 'Restos de desbroce dejados en el suelo'),
        ];
      default:
        return const [];
    }
  }
}

/// El estado del cultivo, en palabras. El código BBCH exacto depende del
/// cultivo y llegará con el catálogo oficial (ADR-0014): de momento se guarda
/// el nombre, que es lo que el agricultor reconoce.
class _EstadoFenologico extends StatelessWidget {
  const _EstadoFenologico({required this.estado});

  final _ActivityFormScreenState estado;

  @override
  Widget build(BuildContext context) {
    final valor = estado._detalle['phenologicalStageLabel'] as String?;
    return DropdownButtonFormField<String>(
      initialValue: estadosFenologicos.contains(valor) ? valor : null,
      decoration: const InputDecoration(labelText: 'Estado del cultivo'),
      items: [
        for (final fase in estadosFenologicos) DropdownMenuItem(value: fase, child: Text(fase)),
      ],
      onChanged: (elegido) =>
          estado.actualizar(() => estado._detalle['phenologicalStageLabel'] = elegido),
    );
  }
}
