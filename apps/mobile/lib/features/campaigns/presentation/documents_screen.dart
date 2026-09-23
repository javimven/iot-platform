import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import '../data/document_models.dart';
import 'adjuntos.dart';
import 'campaign_labels.dart';
import 'campaigns_screen.dart' show MensajeDeCampanas;

/// Todo lo adjuntado en una campaña: lo que cuelga de ella y lo que cuelga de
/// cada actividad, en un sitio. Buscar la analítica del agua no puede obligar
/// a recorrer la línea de tiempo.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({required this.campana, super.key});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentos = ref.watch(documentosProvider(campana.id));
    final permisos = ref.watch(permisosDeCampanaProvider);
    final sePuedeTocar = permisos.puedeRegistrar && !campana.resumen.estaCerrada;

    return Scaffold(
      appBar: AppBar(title: const Text('Fotos y documentos')),
      body: documentos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MensajeDeCampanas(
          icono: Icons.cloud_off,
          titulo: 'No se pudieron cargar los documentos',
          detalle: mensajeDeError(error),
        ),
        data: (lista) {
          final deActividades = lista.where((d) => d.activityId != null).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(documentosProvider(campana.id)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  'De la campaña',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'La analítica del agua, el plan de abonado, el contrato… lo que vale para '
                  'toda la campaña y no para un día concreto.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Adjuntos(campaignId: campana.id, sePuedeTocar: sePuedeTocar),
                const SizedBox(height: 24),
                Text('De las actividades', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (deActividades.isEmpty)
                  Text(
                    'Todavía no hay fotos en las actividades. Se añaden desde la propia '
                    'actividad, en la línea de tiempo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final documento in deActividades)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FilaDeDocumento(documento: documento),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilaDeDocumento extends StatelessWidget {
  const _FilaDeDocumento({required this.documento});

  final DocumentoDelCuaderno documento;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => verDocumento(context, documento),
      child: Row(
        children: [
          Icon(
            documento.esImagen ? Icons.image_outlined : Icons.description_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(documento.nombre, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${etiquetaDeDocumento(documento.documentType)} · '
                  '${tamanoLegible(documento.byteSize)} · ${fechaCorta(documento.createdAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
