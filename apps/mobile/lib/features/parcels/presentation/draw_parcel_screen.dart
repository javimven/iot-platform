import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../installations/application/installations_controller.dart';
import '../../satellite/presentation/parcel_map.dart';
import '../application/parcels_controller.dart';
import '../data/parcel_models.dart';

/// Vértices mínimos para encerrar una superficie.
const _minimoVertices = 3;

/// Dibujo de una parcela nueva (BACKLOG.md #36): se toca el mapa para ir
/// poniendo vértices y se guarda con un nombre.
///
/// En la v1 no hay importar ficheros ni traer recintos del catastro: se dibuja
/// a mano, que es lo que pidió el usuario y lo que no depende de ninguna
/// integración más.
class DrawParcelScreen extends ConsumerStatefulWidget {
  const DrawParcelScreen({required this.installationId, super.key});

  final String installationId;

  @override
  ConsumerState<DrawParcelScreen> createState() => _DrawParcelScreenState();
}

class _DrawParcelScreenState extends ConsumerState<DrawParcelScreen> {
  final _vertices = <LatLng>[];
  final _nombre = TextEditingController();
  final _mapa = MapController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  bool get _sePuedeGuardar =>
      _vertices.length >= _minimoVertices && _nombre.text.trim().isNotEmpty && !_guardando;

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final parcela = await ref.read(parcelsApiProvider).crear(
            installationId: widget.installationId,
            name: _nombre.text.trim(),
            contorno: ContornoParcela([
              [_vertices],
            ]),
          );
      // Al volver, la lista de la finca tiene que traer la nueva.
      ref.invalidate(parcelasDeFincaProvider(widget.installationId));
      ref.read(parcelaSeleccionadaProvider.notifier).state = parcela.id;
      if (mounted) {
        Navigator.of(context).pop(parcela.id);
      }
    } catch (error) {
      setState(() {
        _guardando = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final finca = ref.watch(installationProvider(widget.installationId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dibujar parcela'),
        actions: [
          if (_vertices.isNotEmpty)
            IconButton(
              tooltip: 'Deshacer el último vértice',
              icon: const Icon(Icons.undo),
              onPressed: () => setState(() => _vertices.removeLast()),
            ),
          if (_vertices.isNotEmpty)
            IconButton(
              tooltip: 'Empezar de nuevo',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(_vertices.clear),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ParcelMap(
              controller: _mapa,
              anillos: const [],
              // Se encuadra en la finca si tiene coordenadas: casi siempre es
              // donde está la parcela, y ahorra buscarla por el mapa.
              centro: finca.maybeWhen(
                data: (f) => f.latitude != null && f.longitude != null
                    ? LatLng(f.latitude!, f.longitude!)
                    : null,
                orElse: () => null,
              ),
              verticesEnCurso: _vertices,
              // Buscar pueblo, calle o coordenadas, y mi ubicación: para
              // llegar a la parcela antes de dibujarla.
              buscador: true,
              onTap: (punto) => setState(() => _vertices.add(punto)),
            ),
          ),
          SafeArea(
            top: false,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _vertices.length < _minimoVertices
                        ? 'Busca el sitio arriba o usa tu ubicación, y toca el mapa para marcar las '
                            'esquinas de la parcela (mínimo 3).'
                        : '${_vertices.length} vértices. El contorno se cierra solo al guardar.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nombre,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la parcela',
                      hintText: 'La Vega, El Olivar…',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Guardar parcela',
                          loading: _guardando,
                          onPressed: _sePuedeGuardar ? _guardar : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        label: 'Cancelar',
                        variant: AppButtonVariant.secondary,
                        onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
