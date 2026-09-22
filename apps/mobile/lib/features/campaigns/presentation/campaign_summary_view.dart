import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;

/// Cómo va la campaña, a partir de lo registrado. Un apartado sin actividades
/// no sale: un "0 m³" al lado de "Riego" parecería una medida, y lo que pasa
/// es que no hay dato.
class CampaignSummaryView extends ConsumerWidget {
  const CampaignSummaryView({required this.campaignId, super.key});

  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenCampanaProvider(campaignId));

    return resumen.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudo cargar el resumen',
        detalle: mensajeDeError(error),
      ),
      data: (datos) => datos.vacio
          ? const MensajeDeCampanas(
              icono: Icons.insights_outlined,
              titulo: 'Sin datos todavía',
              detalle: 'El resumen se calcula con lo que vayas registrando.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: _secciones(context, datos),
            ),
    );
  }

  List<Widget> _secciones(BuildContext context, ResumenCampana datos) {
    final riego = datos.riego;
    final abonado = datos.abonado;
    final tratamientos = datos.tratamientos;
    final cosecha = datos.cosecha;

    return [
      if (riego != null)
        _Seccion(
          icono: iconoDeTipo('irrigation'),
          titulo: 'Riego',
          cifras: [
            (etiqueta: 'Total', valor: '${cifra(riego.volumeM3)} m³'),
            if (riego.volumeM3PerHa != null)
              (etiqueta: 'Por hectárea', valor: '${cifraCorta(riego.volumeM3PerHa!)} m³/ha'),
          ],
          aviso: riego.withoutVolume == 0
              ? null
              : '${riego.withoutVolume} ${riego.withoutVolume == 1 ? 'riego' : 'riegos'} sin cantidad apuntada',
        ),
      if (abonado != null)
        _Seccion(
          icono: iconoDeTipo('fertilization'),
          titulo: 'Fertilización',
          cifras: [
            if (abonado.nKgHa != null)
              (etiqueta: 'N', valor: '${cifraCorta(abonado.nKgHa!)} kg/ha'),
            if (abonado.p2o5KgHa != null)
              (etiqueta: 'P₂O₅', valor: '${cifraCorta(abonado.p2o5KgHa!)} kg/ha'),
            if (abonado.k2oKgHa != null)
              (etiqueta: 'K₂O', valor: '${cifraCorta(abonado.k2oKgHa!)} kg/ha'),
            (etiqueta: 'Aplicaciones', valor: '${abonado.count}'),
          ],
          aviso: abonado.withoutComposition == 0
              ? null
              : '${abonado.withoutComposition} sin riqueza apuntada: no cuentan en los kg por hectárea',
        ),
      if (tratamientos != null)
        _Seccion(
          icono: iconoDeTipo('phytosanitary'),
          titulo: 'Tratamientos fitosanitarios',
          cifras: [
            (etiqueta: 'Tratamientos', valor: '${tratamientos.count}'),
            (etiqueta: 'Productos distintos', valor: '${tratamientos.distinctProducts}'),
          ],
        ),
      if (cosecha != null)
        _Seccion(
          icono: iconoDeTipo('harvest'),
          titulo: 'Recolección',
          cifras: [
            (etiqueta: 'Total', valor: '${cifra(cosecha.quantityKg)} kg'),
            if (cosecha.yieldKgHa != null)
              (etiqueta: 'Rendimiento', valor: '${cifra(cosecha.yieldKgHa!)} kg/ha'),
            if (cosecha.expectedYieldKgHa != null)
              (etiqueta: 'Esperado', valor: '${cifra(cosecha.expectedYieldKgHa!)} kg/ha'),
          ],
          aviso: cosecha.withoutKg == 0
              ? null
              : '${cosecha.withoutKg} sin kilos apuntados (o contados en unidades)',
        ),
      if (datos.labores != null)
        _Seccion(
          icono: iconoDeTipo('field_work'),
          titulo: 'Labores',
          cifras: [(etiqueta: 'Labores', valor: '${datos.labores}')],
        ),
      if (datos.observaciones != null)
        _Seccion(
          icono: iconoDeTipo('observation'),
          titulo: 'Observaciones',
          cifras: [(etiqueta: 'Anotadas', valor: '${datos.observaciones}')],
        ),
      if (datos.unidades.length > 1) _PorCultivo(unidades: datos.unidades),
    ];
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.icono,
    required this.titulo,
    required this.cifras,
    this.aviso,
  });

  final IconData icono;
  final String titulo;
  final List<({String etiqueta, String valor})> cifras;
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(titulo, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                for (final cifra in cifras)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cifra.etiqueta, style: theme.textTheme.labelSmall),
                      Text(cifra.valor, style: theme.textTheme.titleMedium),
                    ],
                  ),
              ],
            ),
            if (aviso != null) ...[
              const SizedBox(height: 8),
              Text(aviso!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _PorCultivo extends StatelessWidget {
  const _PorCultivo({required this.unidades});

  final List<({String cropName, double areaHa, double? harvestKg, double? yieldKgHa})> unidades;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Por cultivo', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final unidad in unidades)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text(unidad.cropName, style: theme.textTheme.bodyMedium)),
                  Text(superficie(unidad.areaHa), style: theme.textTheme.bodySmall),
                  if (unidad.yieldKgHa != null) ...[
                    const SizedBox(width: 12),
                    Text('${cifra(unidad.yieldKgHa!)} kg/ha', style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
