import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../installations/application/installations_controller.dart';
import '../../installations/data/installation_models.dart';
import '../../parcels/application/parcels_controller.dart';
import '../../parcels/data/parcel_models.dart';
import '../application/satellite_controller.dart';
import '../data/satellite_models.dart';
import 'ndvi_chart.dart';
import 'ndvi_legend.dart';
import 'parcel_map.dart';

/// Por debajo de estos píxeles de Sentinel-2 (10 m de lado), la media mezcla
/// el interior con los bordes y conviene decirlo.
const _pixelesParaFiarse = 25;

/// Sección Satélite (BACKLOG.md #36).
///
/// La navegación de la app es estación-céntrica y no se toca: esta pantalla es
/// la puerta de entrada al concepto de parcela, que solo existe aquí.
///
///   finca → parcela → mapa con NDVI + calidad + evolución
class SatelliteScreen extends ConsumerWidget {
  const SatelliteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fincas = ref.watch(installationsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Satélite')),
      body: fincas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Mensaje(
          icono: Icons.cloud_off,
          titulo: 'No se pudieron cargar las fincas',
          detalle: '$error',
        ),
        data: (lista) => lista.isEmpty
            ? const _Mensaje(
                icono: Icons.agriculture_outlined,
                titulo: 'Todavía no hay fincas',
                detalle: 'Crea una finca en Infraestructura para poder dibujar parcelas.',
              )
            : _ContenidoSatelite(fincas: lista),
      ),
    );
  }
}

class _ContenidoSatelite extends ConsumerWidget {
  const _ContenidoSatelite({required this.fincas});

  final List<Installation> fincas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seleccionada = ref.watch(fincaSeleccionadaProvider) ?? fincas.first.id;
    final parcelas = ref.watch(parcelasDeFincaProvider(seleccionada));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DropdownButtonFormField<String>(
            initialValue: seleccionada,
            decoration: const InputDecoration(labelText: 'Finca'),
            items: [
              for (final finca in fincas)
                DropdownMenuItem(value: finca.id, child: Text(finca.name)),
            ],
            onChanged: (id) {
              if (id == null) return;
              ref.read(fincaSeleccionadaProvider.notifier).state = id;
              // La parcela elegida era de la finca anterior.
              ref.read(parcelaSeleccionadaProvider.notifier).state = null;
            },
          ),
        ),
        Expanded(
          child: parcelas.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            // La primera ruta del modulo es la de parcelas: si la organizacion
            // no tiene el satelite contratado, el backend responde aqui 403
            // (FeatureGuard) y se explica el plan en vez de ensenar el error.
            error: (error, _) => esModuloNoContratado(error)
                ? const _Mensaje(
                    icono: Icons.lock_outline,
                    titulo: 'El satélite no está incluido en tu plan',
                    detalle:
                        'Contacta con el administrador de tu organización para activar las imágenes por satélite.',
                  )
                : _Mensaje(
                    icono: Icons.cloud_off,
                    titulo: 'No se pudieron cargar las parcelas',
                    detalle: '$error',
                  ),
            data: (lista) => lista.isEmpty
                ? _SinParcelas(installationId: seleccionada)
                : _ParcelaElegida(installationId: seleccionada, parcelas: lista),
          ),
        ),
      ],
    );
  }
}

/// Finca sin parcelas: lo único que cabe hacer aquí es dibujar una.
class _SinParcelas extends StatelessWidget {
  const _SinParcelas({required this.installationId});

  final String installationId;

  @override
  Widget build(BuildContext context) {
    return _Mensaje(
      icono: Icons.crop_free,
      titulo: 'Esta finca no tiene parcelas',
      detalle:
          'Dibuja el contorno de una parcela sobre el mapa para empezar a ver su NDVI por satélite.',
      accion: AppButton(
        label: 'Crear parcela',
        icon: Icons.add_location_alt_outlined,
        onPressed: () => abrirDibujoDeParcela(context, installationId),
      ),
    );
  }
}

class _ParcelaElegida extends ConsumerWidget {
  const _ParcelaElegida({required this.installationId, required this.parcelas});

  final String installationId;
  final List<Parcel> parcelas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(parcelaSeleccionadaProvider);
    final parcela = parcelas.firstWhere(
      (p) => p.id == elegida,
      orElse: () => parcelas.first,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: parcela.id,
                decoration: const InputDecoration(labelText: 'Parcela'),
                items: [
                  for (final p in parcelas) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (id) =>
                    ref.read(parcelaSeleccionadaProvider.notifier).state = id,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Crear otra parcela',
              icon: const Icon(Icons.add_location_alt_outlined),
              onPressed: () => abrirDibujoDeParcela(context, installationId),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _FichaParcela(parcela: parcela),
      ],
    );
  }
}

class _FichaParcela extends ConsumerWidget {
  const _FichaParcela({required this.parcela});

  final Parcel parcela;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ultima = ref.watch(ultimaObservacionProvider(parcela.id));
    final serie = ref.watch(serieNdviProvider(parcela.id));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ultima.when(
          loading: () => const AppCard(
            child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          ),
          error: (error, _) => AppCard(
            child: _Mensaje(
              icono: Icons.cloud_off,
              titulo: 'No se pudo consultar el satélite',
              detalle: '$error',
            ),
          ),
          data: (observacion) => observacion == null
              ? _SinObservaciones(parcela: parcela)
              : _ObservacionActual(parcela: parcela, observacion: observacion),
        ),
        const SizedBox(height: 16),
        Text('Evolución del NDVI', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        serie.when(
          loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
          error: (error, _) => Text('No se pudo cargar la evolución.\n$error',
              style: theme.textTheme.bodySmall),
          data: (puntos) => puntos.isEmpty
              ? Text(
                  'Todavía no hay suficientes observaciones para dibujar la evolución.',
                  style: theme.textTheme.bodyMedium,
                )
              : NdviChart(puntos: puntos),
        ),
        const SizedBox(height: 16),
        _NotaParcela(parcela: parcela),
      ],
    );
  }
}

/// Parcela recién creada, o sin ninguna pasada utilizable todavía. Nunca se
/// enseña un 0,00 como si fuera un NDVI: no hay dato, que es distinto.
class _SinObservaciones extends ConsumerWidget {
  const _SinObservaciones({required this.parcela});

  final Parcel parcela;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: _Mensaje(
        icono: Icons.satellite_alt_outlined,
        titulo: 'Sin observaciones todavía',
        detalle:
            'Se buscan pasadas nuevas cada día. Una parcela recién creada puede tardar un rato en '
            'tener su primera imagen, y los días muy nublados se descartan.',
        accion: AppButton(
          label: 'Buscar ahora',
          variant: AppButtonVariant.secondary,
          icon: Icons.refresh,
          onPressed: () => _refrescar(context, ref, parcela.id),
        ),
      ),
    );
  }
}

class _ObservacionActual extends ConsumerStatefulWidget {
  const _ObservacionActual({required this.parcela, required this.observacion});

  final Parcel parcela;
  final ObservacionSatelite observacion;

  @override
  ConsumerState<_ObservacionActual> createState() => _ObservacionActualState();
}

class _ObservacionActualState extends ConsumerState<_ObservacionActual> {
  double _opacidad = 0.8;

  @override
  Widget build(BuildContext context) {
    final observacion = widget.observacion;
    final parcela = widget.parcela;
    final theme = Theme.of(context);
    final fecha = DateFormat('dd/MM/yyyy').format(observacion.acquisitionTime.toLocal());
    final enlace = ref.watch(
      enlaceImagenNdviProvider((parcelId: parcela.id, observacion: observacion)),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Observación del $fecha', style: theme.textTheme.titleMedium),
              ),
              _ChipCalidad(calidad: observacion.calidad),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sentinel-2 · resolución de 10 m por píxel',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 260,
              child: ParcelMap(
                anillos: parcela.contorno.anillosExteriores,
                centro: parcela.centro,
                opacidadImagen: _opacidad,
                imagen: enlace.maybeWhen(
                  data: (e) => e == null
                      ? null
                      : (
                          url: e.url,
                          bounds: LatLngBounds(
                            LatLng(parcela.bbox[1], parcela.bbox[0]),
                            LatLng(parcela.bbox[3], parcela.bbox[2]),
                          ),
                        ),
                  orElse: () => null,
                ),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.opacity, size: 18),
              Expanded(
                child: Slider(
                  value: _opacidad,
                  onChanged: (v) => setState(() => _opacidad = v),
                ),
              ),
            ],
          ),
          const NdviLegend(),
          const SizedBox(height: 16),
          _Cifras(observacion: observacion),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Actualizar',
              variant: AppButtonVariant.secondary,
              icon: Icons.refresh,
              onPressed: () => _refrescar(context, ref, parcela.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.observacion});

  final ObservacionSatelite observacion;

  @override
  Widget build(BuildContext context) {
    final ndvi = observacion.ndvi;
    final theme = Theme.of(context);
    if (ndvi == null) {
      return Text('Esta observación no tiene datos de NDVI.', style: theme.textTheme.bodyMedium);
    }

    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _Cifra(titulo: 'NDVI medio', valor: ndvi.mean.toStringAsFixed(2)),
        // La mediana aguanta mejor cuatro píxeles raros en el borde.
        _Cifra(titulo: 'NDVI mediano', valor: ndvi.median.toStringAsFixed(2)),
        _Cifra(
          titulo: 'Superficie válida',
          valor: observacion.calidad.validPixelPercent == null
              ? '—'
              : '${observacion.calidad.validPixelPercent} %',
        ),
      ],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: theme.textTheme.labelMedium),
        Text(valor, style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

class _ChipCalidad extends StatelessWidget {
  const _ChipCalidad({required this.calidad});

  final CalidadObservacion calidad;

  @override
  Widget build(BuildContext context) {
    final porcentaje = calidad.validPixelPercent;
    return switch (calidad.status) {
      'good' => StatusChip(label: '$porcentaje % válido', tone: AppStatusTone.ok),
      'partial' => StatusChip(label: '$porcentaje % válido', tone: AppStatusTone.warn),
      _ => const StatusChip(label: 'Sin calidad', tone: AppStatusTone.neutral),
    };
  }
}

/// Avisos de la parcela: lo que hay que saber para no leer mal las cifras.
class _NotaParcela extends StatelessWidget {
  const _NotaParcela({required this.parcela});

  final Parcel parcela;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avisos = <String>[
      '${parcela.areaHa.toStringAsFixed(2)} ha · unos ${parcela.pixelesAproximados} píxeles de Sentinel-2.',
      if (parcela.pixelesAproximados < _pixelesParaFiarse)
        'La parcela es pequeña para una resolución de 10 m: la media puede estar mezclada con lo que hay justo fuera del contorno.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final aviso in avisos)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(aviso, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
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
            Icon(icono, size: 40, color: theme.colorScheme.outline),
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

/// El backend protege el modulo con `FeatureGuard`: una organizacion sin
/// `satellite_imagery` recibe 403 con ese titulo. Se distingue de otros 403
/// (fuera de alcance, sin permiso) por el titulo, que es lo que expone el
/// filtro RFC 7807.
bool esModuloNoContratado(Object error) =>
    error is ApiException &&
    error.status == 403 &&
    error.title.startsWith('Feature not enabled');

/// Ruta del dibujo de una parcela nueva, fuera del shell (es pantalla completa).
void abrirDibujoDeParcela(BuildContext context, String installationId) {
  context.push('/installations/$installationId/parcels/new');
}

Future<void> _refrescar(BuildContext context, WidgetRef ref, String parcelId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(satelliteApiProvider).refrescar(parcelId);
    ref.invalidate(ultimaObservacionProvider(parcelId));
    ref.invalidate(serieNdviProvider(parcelId));
    messenger.showSnackBar(
      const SnackBar(content: Text('Buscando pasadas nuevas. Puede tardar unos minutos.')),
    );
  } catch (error) {
    // El backend responde 429 si ya se buscó hace menos de una hora: cada
    // búsqueda gasta cuota de Copernicus.
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}
