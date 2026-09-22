import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/campaigns_controller.dart';
import '../data/activity_models.dart';
import '../data/campaign_models.dart';
import 'activity_form_screen.dart';
import 'activity_sheet.dart';
import 'campaign_labels.dart';
import 'campaign_summary_view.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;
import 'cerrar_campana.dart';
import 'completeness_view.dart';
import 'notebook_catalog_screen.dart';
import 'notebook_wizard.dart';

enum _Vista { actividad, resumen, revision }

/// Ficha de una campaña: lo que se ha hecho y cómo va. El botón grande es
/// "Registrar actividad": el agricultor trabaja con actividades, y el
/// cuaderno se construye solo por debajo (BACKLOG.md #60).
class CampaignDetailScreen extends ConsumerStatefulWidget {
  const CampaignDetailScreen({required this.campaignId, super.key});

  final String campaignId;

  @override
  ConsumerState<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> {
  _Vista _vista = _Vista.actividad;

  @override
  Widget build(BuildContext context) {
    final campana = ref.watch(campanaProvider(widget.campaignId));

    return Scaffold(
      appBar: AppBar(
        title: Text(campana.valueOrNull?.resumen.name ?? 'Campaña'),
        actions: [
          if (campana.valueOrNull != null) _MenuDeCampana(campana: campana.value!),
        ],
      ),
      body: campana.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MensajeDeCampanas(
          icono: Icons.cloud_off,
          titulo: 'No se pudo cargar la campaña',
          detalle: mensajeDeError(error),
        ),
        data: (datos) {
          // Si se está mirando la revisión de una campaña que ya no es un
          // cuaderno completo, el botón de ese segmento no existe y
          // SegmentedButton no admite un valor que no esté entre ellos.
          if (_vista == _Vista.revision && !datos.resumen.esCompleta) {
            _vista = _Vista.actividad;
          }
          return Column(
            children: [
              _Cabecera(campana: datos),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SegmentedButton<_Vista>(
                  segments: [
                    const ButtonSegment(value: _Vista.actividad, label: Text('Actividad')),
                    const ButtonSegment(value: _Vista.resumen, label: Text('Resumen')),
                    // La revisión solo tiene sentido en un cuaderno completo
                    // (ADR-0013): la campaña sencilla no prometió uno.
                    if (datos.resumen.esCompleta)
                      const ButtonSegment(value: _Vista.revision, label: Text('Revisión')),
                  ],
                  selected: {_vista},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _vista = s.first),
                ),
              ),
              Expanded(
                child: switch (_vista) {
                  _Vista.actividad => _LineaDeTiempo(campana: datos),
                  _Vista.resumen => CampaignSummaryView(campaignId: widget.campaignId),
                  _Vista.revision => CompletenessView(campana: datos),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cabecera extends ConsumerWidget {
  const _Cabecera({required this.campana});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final resumen = campana.resumen;
    final permisos = ref.watch(permisosDeCampanaProvider);
    final ultima = resumen.lastActivity;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(resumen.name, style: theme.textTheme.titleMedium)),
                StatusChip(
                  label: resumen.estaCerrada ? 'Finalizada' : 'Activa',
                  tone: resumen.estaCerrada ? AppStatusTone.neutral : AppStatusTone.ok,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${resumen.installationName} · ${superficie(resumen.areaHa)} · '
              '${resumen.parcelCount} ${resumen.parcelCount == 1 ? 'parcela' : 'parcelas'}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              [
                'Inicio: ${fechaCorta(resumen.startDate)}',
                if (resumen.endDate != null) 'Fin: ${fechaCorta(resumen.endDate!)}',
                if (resumen.endDate == null && resumen.expectedEndDate != null)
                  'Fin previsto: ${fechaCorta(resumen.expectedEndDate!)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (campana.cropUnits.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                campana.cropUnits.map((u) => u.nombre).join(', '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (ultima != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(iconoDeTipo(ultima.type),
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Última actividad: ${etiquetaDeTipo(ultima.type).toLowerCase()} · '
                    '${diaRelativo(ultima.date).toLowerCase()}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (permisos.puedeRegistrar && !resumen.estaCerrada) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Registrar actividad',
                icon: Icons.add,
                expand: true,
                onPressed: () => elegirTipoDeActividad(context, campana.id),
              ),
            ],
            if (resumen.estaCerrada) ...[
              const SizedBox(height: 8),
              Text(
                'Campaña cerrada: su cuaderno queda como estaba. Para corregir algo, reábrela.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuDeCampana extends ConsumerWidget {
  const _MenuDeCampana({required this.campana});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosDeCampanaProvider);
    final cerrada = campana.resumen.estaCerrada;

    return PopupMenuButton<String>(
      onSelected: (opcion) async {
        switch (opcion) {
          case 'cerrar':
            await cerrarCampana(context, ref, campana);
          case 'reabrir':
            await reabrirCampana(context, ref, campana);
          case 'borrar':
            await borrarCampana(context, ref, campana);
          case 'cuaderno':
            await pasarACuadernoCompleto(context, ref, campana);
          case 'cuestionario':
            await cambiarCuestionario(context, ref, campana);
          case 'catalogos':
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotebookCatalogScreen()),
            );
        }
      },
      itemBuilder: (context) => [
        if (permisos.puedeCrear && !cerrada && !campana.resumen.esCompleta)
          const PopupMenuItem(value: 'cuaderno', child: Text('Pasar a cuaderno completo')),
        if (permisos.puedeCrear && !cerrada && campana.resumen.esCompleta)
          const PopupMenuItem(value: 'cuestionario', child: Text('Cuestionario del cuaderno')),
        const PopupMenuItem(value: 'catalogos', child: Text('Personas y equipos')),
        if (permisos.puedeCerrar && !cerrada)
          const PopupMenuItem(value: 'cerrar', child: Text('Cerrar campaña')),
        if (permisos.puedeCerrar && cerrada)
          const PopupMenuItem(value: 'reabrir', child: Text('Reabrir campaña')),
        if (permisos.puedeBorrar && !cerrada)
          const PopupMenuItem(value: 'borrar', child: Text('Eliminar campaña')),
      ],
    );
  }
}

/// La línea de tiempo, agrupada por día: "Hoy", "Ayer", "18 sep".
class _LineaDeTiempo extends ConsumerWidget {
  const _LineaDeTiempo({required this.campana});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actividades = ref.watch(actividadesProvider(campana.id));
    final permisos = ref.watch(permisosDeCampanaProvider);

    return actividades.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudo cargar la actividad',
        detalle: mensajeDeError(error),
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return MensajeDeCampanas(
            icono: Icons.history_toggle_off,
            titulo: 'Todavía no has apuntado nada',
            detalle: permisos.puedeRegistrar && !campana.resumen.estaCerrada
                ? 'Apunta lo que vayas haciendo —un riego, un abonado, un tratamiento— y el cuaderno se va solo.'
                : 'Cuando se registre algo en esta campaña, aparecerá aquí.',
          );
        }

        final elementos = <Widget>[];
        String? diaAnterior;
        for (final actividad in lista) {
          final dia = diaRelativo(actividad.startDate);
          if (dia != diaAnterior) {
            elementos.add(Padding(
              padding: EdgeInsets.fromLTRB(4, elementos.isEmpty ? 4 : 16, 4, 6),
              child: Text(dia.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            ));
            diaAnterior = dia;
          }
          elementos.add(_FilaDeActividad(actividad: actividad, campana: campana));
        }

        return RefreshIndicator(
          onRefresh: () async => refrescarCampana(ref, campana.id),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: elementos,
          ),
        );
      },
    );
  }
}

class _FilaDeActividad extends StatelessWidget {
  const _FilaDeActividad({required this.actividad, required this.campana});

  final Actividad actividad;
  final Campana campana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detalle = resumenDeActividad(actividad);
    final parcelas = actividad.targets.map((d) => d.parcelName).join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: () => abrirActividad(context, campana, actividad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconoDeTipo(actividad.type), color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child:
                            Text(etiquetaDeTipo(actividad.type), style: theme.textTheme.titleSmall),
                      ),
                      if (actividad.esDeVariosDias)
                        Text(
                          '${fechaCorta(actividad.startDate)} – ${fechaCorta(actividad.endDate)}',
                          style: theme.textTheme.labelSmall,
                        )
                      else if (actividad.startTime != null)
                        Text(actividad.startTime!, style: theme.textTheme.labelSmall),
                    ],
                  ),
                  if (detalle != null && detalle.isNotEmpty)
                    Text(detalle, style: theme.textTheme.bodyMedium),
                  if (parcelas.isNotEmpty) Text(parcelas, style: theme.textTheme.bodySmall),
                  if (actividad.notes != null && actividad.notes!.isNotEmpty)
                    Text(
                      actividad.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué has hecho: la rejilla de tipos, que es por donde empieza todo.
Future<void> elegirTipoDeActividad(BuildContext context, String campaignId) async {
  final tipo = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué has hecho?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final tipo in tiposDeActividad)
              ListTile(
                leading: Icon(iconoDeTipo(tipo)),
                title: Text(etiquetaDeTipo(tipo)),
                onTap: () => Navigator.of(context).pop(tipo),
              ),
          ],
        ),
      ),
    ),
  );
  if (tipo == null || !context.mounted) return;

  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ActivityFormScreen(campaignId: campaignId, tipo: tipo),
    ),
  );
}
