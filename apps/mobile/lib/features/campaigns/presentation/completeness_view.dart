import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import '../data/notebook_models.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;

/// La revisión del cuaderno completo: qué información falta y qué conviene
/// mirar, cada cosa con la fuente por la que se pide.
///
/// **No dice que la campaña "cumpla"** (ADR-0013): la obligación depende de la
/// ubicación, el tamaño, las ayudas y cosas que la app no conoce. Y no bloquea
/// nada: se apunta lo que se sabe y se completa después.
class CompletenessView extends ConsumerWidget {
  const CompletenessView({required this.campana, super.key});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revision = ref.watch(revisionDelCuadernoProvider(campana.id));

    return revision.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => MensajeDeCampanas(
        icono: Icons.cloud_off,
        titulo: 'No se pudo revisar el cuaderno',
        detalle: mensajeDeError(error),
      ),
      data: (datos) {
        if (!datos.aplica) {
          return const MensajeDeCampanas(
            icono: Icons.menu_book_outlined,
            titulo: 'Esta campaña es sencilla',
            detalle: 'La revisión es del cuaderno de explotación completo. Puedes pasar a cuaderno '
                'completo desde el menú de la campaña; lo ya apuntado se conserva.',
          );
        }
        if (datos.sinPendientes) {
          return MensajeDeCampanas(
            icono: Icons.task_alt,
            titulo: 'No falta nada por apuntar',
            detalle: 'Revisado con las reglas ${datos.versionDeReglas}. '
                'Esto no es una comprobación legal: dice que no falta información, '
                'no que el cuaderno sea válido para una inspección.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(revisionDelCuadernoProvider(campana.id)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              ResumenDeRevision(revision: datos),
              if (datos.deLaCampana.isNotEmpty) ...[
                const _Titulo('De la campaña y la finca'),
                for (final aviso in datos.deLaCampana) _FilaDeAviso(aviso: aviso),
              ],
              for (final actividad in datos.deActividades) ...[
                _Titulo(
                  '${etiquetaDeTipo(actividad.type)}'
                  '${actividad.date == null ? '' : ' · ${fechaCorta(actividad.date!)}'}',
                ),
                for (final aviso in actividad.avisos) _FilaDeAviso(aviso: aviso),
              ],
              const SizedBox(height: 16),
              Text(
                'Revisado con las reglas ${datos.versionDeReglas}. La plataforma no certifica '
                'que el cuaderno cumpla: señala la información que falta según esas reglas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// La cuenta de lo pendiente, para la ficha y para el diálogo de cierre.
class ResumenDeRevision extends StatelessWidget {
  const ResumenDeRevision({required this.revision, super.key});

  final RevisionDelCuaderno revision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(
            revision.faltan > 0
                ? Icons.assignment_late_outlined
                : Icons.assignment_turned_in_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textoDePendientes(revision), style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Puedes seguir apuntando y completarlo después.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: revision.faltan > 0 ? 'Pendiente' : 'Revisar',
            tone: revision.faltan > 0 ? AppStatusTone.warn : AppStatusTone.neutral,
          ),
        ],
      ),
    );
  }
}

/// "3 datos pendientes y 1 aviso", en singular y plural de verdad.
String textoDePendientes(RevisionDelCuaderno revision) {
  if (revision.sinPendientes) return 'No falta nada por apuntar';
  final partes = <String>[
    if (revision.faltan > 0)
      '${revision.faltan} ${revision.faltan == 1 ? 'dato pendiente' : 'datos pendientes'}',
    if (revision.avisos > 0) '${revision.avisos} ${revision.avisos == 1 ? 'aviso' : 'avisos'}',
  ];
  return partes.join(' y ');
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(texto.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _FilaDeAviso extends StatelessWidget {
  const _FilaDeAviso({required this.aviso});

  final AvisoDelCuaderno aviso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              aviso.esFalta ? Icons.radio_button_unchecked : Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(aviso.label, style: theme.textTheme.bodyMedium),
                  if (aviso.why.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(aviso.why, style: theme.textTheme.bodySmall),
                  ],
                  if (aviso.sourceLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(aviso.sourceLabel, style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
