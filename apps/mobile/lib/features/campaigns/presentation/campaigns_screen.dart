import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../installations/application/installations_controller.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import 'campaign_labels.dart';

/// Sección Campañas (BACKLOG.md #60). La lista de campañas de la
/// organización, dentro del alcance del miembro.
class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campanas = ref.watch(campanasProvider);
    final permisos = ref.watch(permisosDeCampanaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Campañas')),
      body: Column(
        children: [
          const _Filtros(),
          Expanded(
            child: campanas.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => esModuloNoContratado(error)
                  ? const MensajeDeCampanas(
                      icono: Icons.lock_outline,
                      titulo: 'Las campañas no están incluidas en tu plan',
                      detalle:
                          'Contacta con el administrador de tu organización para activar el cuaderno de campo.',
                    )
                  : MensajeDeCampanas(
                      icono: Icons.cloud_off,
                      titulo: 'No se pudieron cargar las campañas',
                      detalle: mensajeDeError(error),
                    ),
              data: (lista) => lista.isEmpty
                  ? _SinCampanas(puedeCrear: permisos.puedeCrear)
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(campanasProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _TarjetaDeCampana(campana: lista[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(vistaDeCampanasProvider);
    final finca = ref.watch(fincaDeCampanasProvider);
    final fincas = ref.watch(installationsListProvider);
    final permisos = ref.watch(permisosDeCampanaProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<VistaDeCampanas>(
                  segments: const [
                    ButtonSegment(value: VistaDeCampanas.activas, label: Text('Activas')),
                    ButtonSegment(value: VistaDeCampanas.finalizadas, label: Text('Finalizadas')),
                  ],
                  selected: {vista},
                  showSelectedIcon: false,
                  onSelectionChanged: (seleccion) =>
                      ref.read(vistaDeCampanasProvider.notifier).state = seleccion.first,
                ),
              ),
              if (permisos.puedeCrear) ...[
                const SizedBox(width: 12),
                AppButton(
                  label: 'Nueva',
                  icon: Icons.add,
                  onPressed: () => context.push('/campaigns/new'),
                ),
              ],
            ],
          ),
          // El filtro por finca solo tiene sentido con más de una.
          fincas.maybeWhen(
            data: (lista) => lista.length < 2
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String?>(
                      initialValue: finca,
                      decoration: const InputDecoration(labelText: 'Finca'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Todas las fincas')),
                        for (final f in lista)
                          DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                      ],
                      onChanged: (id) => ref.read(fincaDeCampanasProvider.notifier).state = id,
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TarjetaDeCampana extends StatelessWidget {
  const _TarjetaDeCampana({required this.campana});

  final CampanaResumida campana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ultima = campana.lastActivity;

    return AppCard(
      onTap: () => context.push('/campaigns/${campana.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(campana.name, style: theme.textTheme.titleMedium)),
              StatusChip(
                label: campana.estaCerrada ? 'Finalizada' : 'Activa',
                tone: campana.estaCerrada ? AppStatusTone.neutral : AppStatusTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${campana.installationName} · ${superficie(campana.areaHa)} · '
            '${campana.parcelCount} ${campana.parcelCount == 1 ? 'parcela' : 'parcelas'}',
            style: theme.textTheme.bodySmall,
          ),
          if (campana.esCompleta) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('Cuaderno de campo completo', style: theme.textTheme.labelSmall),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                ultima == null ? Icons.schedule : iconoDeTipo(ultima.type),
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ultima == null
                      ? 'Sin actividades registradas'
                      : '${etiquetaDeTipo(ultima.type)} · ${diaRelativo(ultima.date).toLowerCase()}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SinCampanas extends ConsumerWidget {
  const _SinCampanas({required this.puedeCrear});

  final bool puedeCrear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finalizadas = ref.watch(vistaDeCampanasProvider) == VistaDeCampanas.finalizadas;
    if (finalizadas) {
      return const MensajeDeCampanas(
        icono: Icons.inventory_2_outlined,
        titulo: 'Todavía no hay campañas finalizadas',
        detalle: 'Cuando cierres una campaña, su cuaderno quedará guardado aquí.',
      );
    }
    return MensajeDeCampanas(
      icono: Icons.eco_outlined,
      titulo: 'Todavía no hay campañas',
      detalle: puedeCrear
          ? 'Una campaña es lo que cultivas en unas parcelas durante un periodo. '
              'Apunta lo que haces —riegos, abonados, tratamientos, cosecha— y el cuaderno se va solo.'
          : 'Cuando se cree una campaña, aparecerá aquí.',
      accion: puedeCrear
          ? AppButton(
              label: 'Nueva campaña',
              icon: Icons.add,
              onPressed: () => context.push('/campaigns/new'),
            )
          : null,
    );
  }
}

/// Estado vacío o error, con el mismo aire que el resto de la app.
class MensajeDeCampanas extends StatelessWidget {
  const MensajeDeCampanas({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(titulo, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(detalle, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ],
        ),
      ),
    );
  }
}
