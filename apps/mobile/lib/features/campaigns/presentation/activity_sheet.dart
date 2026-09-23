import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../application/campaigns_controller.dart';
import '../data/activity_models.dart';
import '../data/campaign_models.dart';
import 'activity_form_screen.dart';
import 'adjuntos.dart';
import 'campaign_labels.dart';

/// Una actividad al tocarla en la línea de tiempo: qué se hizo, dónde y con
/// qué, y las tres cosas que se pueden hacer con ella (repetirla, corregirla
/// o borrarla). En una campaña cerrada, solo se lee.
Future<void> abrirActividad(BuildContext context, Campana campana, Actividad actividad) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _HojaDeActividad(campana: campana, actividad: actividad),
  );
}

class _HojaDeActividad extends ConsumerWidget {
  const _HojaDeActividad({required this.campana, required this.actividad});

  final Campana campana;
  final Actividad actividad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final permisos = ref.watch(permisosDeCampanaProvider);
    final sePuedeTocar = permisos.puedeRegistrar && !campana.resumen.estaCerrada;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(iconoDeTipo(actividad.type), color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(etiquetaDeTipo(actividad.type), style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                actividad.esDeVariosDias
                    ? 'Del ${fechaCorta(actividad.startDate)} al ${fechaCorta(actividad.endDate)}'
                    : '${fechaLarga(actividad.startDate)}'
                        '${actividad.startTime == null ? '' : ' · ${actividad.startTime}'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _Dato(
                etiqueta: 'Parcelas',
                valor: actividad.targets
                    .map((d) => '${d.parcelName} (${superficie(d.effectiveAreaHa)})')
                    .join(', '),
              ),
              ..._datosDelDetalle(),
              if (actividad.notes != null && actividad.notes!.isNotEmpty)
                _Dato(etiqueta: 'Notas', valor: actividad.notes!),
              if (actividad.origin == 'repeated')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Copiada de otra actividad', style: theme.textTheme.labelSmall),
                ),
              const SizedBox(height: 16),
              Adjuntos(
                campaignId: campana.id,
                activityId: actividad.id,
                sePuedeTocar: sePuedeTocar,
              ),
              if (sePuedeTocar) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Repetir',
                        icon: Icons.copy_all_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _abrirFormulario(context, ModoDeFormulario.repetir),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Corregir',
                        icon: Icons.edit_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _abrirFormulario(context, ModoDeFormulario.editar),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Eliminar',
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.danger,
                  expand: true,
                  onPressed: () => _borrar(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _datosDelDetalle() {
    final detalle = actividad.detalle;
    if (detalle == null) return const [];
    final datos = <Widget>[];

    void dato(String etiqueta, Object? valor) {
      if (valor == null || '$valor'.isEmpty) return;
      datos.add(_Dato(etiqueta: etiqueta, valor: '$valor'));
    }

    String? conUnidad(Object? valor, Object? unidad, Map<String, String> unidades) =>
        valor == null ? null : '${cifraCorta(valor as num)} ${unidades[unidad] ?? ''}'.trim();

    switch (actividad.type) {
      case 'irrigation':
        dato('Cantidad', conUnidad(detalle['amount'], detalle['amountUnit'], unidadesDeRiego));
        dato('Total',
            detalle['volumeM3'] == null ? null : '${cifraCorta(detalle['volumeM3'] as num)} m³');
        dato('Sistema', sistemasDeRiego[detalle['system']]);
        dato('Procedencia del agua', detalle['waterSource']);
      case 'fertilization':
        dato('Producto', detalle['productName']);
        dato('Material', materialesFertilizantes[detalle['materialType']]);
        dato('Dosis', conUnidad(detalle['dose'], detalle['doseUnit'], unidadesDeDosis));
        dato('Forma de aplicación', metodosDeAplicacion[detalle['applicationMethod']]);
        final n = detalle['nKgHa'], p = detalle['p2o5KgHa'], k = detalle['k2oKgHa'];
        if (n != null || p != null || k != null) {
          dato(
            'Aporte',
            '${[
              if (n != null) 'N ${cifraCorta(n as num)}',
              if (p != null) 'P₂O₅ ${cifraCorta(p as num)}',
              if (k != null) 'K₂O ${cifraCorta(k as num)}',
            ].join(' · ')} kg/ha',
          );
        }
      case 'phytosanitary':
        for (final producto in actividad.productos) {
          dato(
            producto['productName'] as String,
            [
              conUnidad(producto['dose'], producto['doseUnit'], unidadesDeDosisFitosanitaria),
              producto['registryNumber'] == null ? null : 'nº ${producto['registryNumber']}',
            ].whereType<String>().join(' · '),
          );
        }
        dato('Problema', detalle['problem'] ?? categoriasDeProblema[detalle['problemCategory']]);
        dato('Estado del cultivo', detalle['phenologicalStageLabel']);
        dato('Eficacia', eficacias[detalle['efficacy']]);
        final aplicador = detalle['applicatorSnapshot'] as Map<String, dynamic>?;
        if (aplicador != null) {
          dato(
            'Aplicador',
            [aplicador['firstName'], aplicador['surname1'], aplicador['companyName']]
                .whereType<String>()
                .join(' '),
          );
        }
      case 'harvest':
        dato(
            'Cantidad', conUnidad(detalle['quantity'], detalle['quantityUnit'], unidadesDeCosecha));
        dato('Producto', detalle['product']);
        dato('Lote', detalle['lotCode']);
        dato('Cliente', detalle['customerName']);
        dato('Destino', detalle['destination']);
      case 'field_work':
        dato('Labor', tiposDeLabor[detalle['workType']]);
        dato('Horas', detalle['hours']);
        dato('Maquinaria', detalle['machinery']);
    }
    return datos;
  }

  Future<void> _abrirFormulario(BuildContext context, ModoDeFormulario modo) async {
    final navegador = Navigator.of(context);
    navegador.pop();
    await navegador.push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityFormScreen(
          campaignId: campana.id,
          tipo: actividad.type,
          base: actividad,
          modo: modo,
        ),
      ),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final navegador = Navigator.of(context);
    final avisos = ScaffoldMessenger.of(context);
    final controlador = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar la actividad?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deja de contar en el cuaderno y en el resumen. Queda guardada con quién la '
              'borró y por qué.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controlador,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await ref.read(campaignsApiProvider).borrarActividad(
            campana.id,
            actividad.id,
            motivo: controlador.text,
          );
      refrescarCampana(ref, campana.id);
      navegador.pop();
    } catch (error) {
      avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: theme.textTheme.labelSmall),
          Text(valor, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
