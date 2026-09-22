import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';

/// Proveedor del mapa base. Separado de la librería a propósito (ADR-0011):
/// una cosa es con qué se dibuja y otra de dónde salen las teselas.
///
/// Por defecto, la **ortofoto PNOA del Instituto Geográfico Nacional**
/// (máxima actualidad, 25-50 cm por píxel). Para mirar un cultivo, una foto
/// aérea vale mucho más que un callejero: el usuario reconoce su parcela por
/// la forma del campo y los caminos, no por el nombre de la calle. Pidió el
/// cambio el usuario al ver el mapa de OpenStreetMap (2026-09-22).
///
/// Licencia comprobada: acceso libre también para uso comercial, compatible
/// con CC BY 4.0 (Orden FOM/2807/2015), **con la atribución obligatoria** que
/// va en [atribucion]. Cubre solo España. El servidor manda
/// `Access-Control-Allow-Origin: *`, así que funciona también en la web.
///
/// Cambiar de proveedor es cambiar una URL: `--dart-define=MAP_TILE_URL` y
/// `MAP_ATTRIBUTION`.
class MapaBase {
  static const urlTeselas = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://www.ign.es/wmts/pnoa-ma?request=GetTile&service=WMTS'
        '&VERSION=1.0.0&Layer=OI.OrthoimageCoverage&Style=default'
        '&Format=image/jpeg&TileMatrixSet=GoogleMapsCompatible'
        '&TileMatrix={z}&TileRow={y}&TileCol={x}',
  );

  /// Texto exacto que exige el IGN como condición de uso.
  static const atribucion = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: 'PNOA cedido por © Instituto Geográfico Nacional de España',
  );

  /// Último nivel con imagen en el servicio del IGN (comprobado: el 21 da 400).
  /// Pasar de ahí sería pedir teselas que no existen.
  static const zoomMaximo = 20.0;

  static const agenteUsuario = 'com.jmvsoluciones.iot_platform';
}

/// Zoom al que se ve una parcela de unas hectáreas entera en pantalla.
const _zoomParcela = 16.0;
const _zoomMinimo = 5.0;

/// Mapa de una parcela: el contorno, una imagen georreferenciada encima si la
/// hay, y los vértices mientras se dibuja.
///
/// Es tonto a propósito: no sabe de NDVI ni de observaciones, solo pinta lo
/// que le den. Así sirve igual para la ficha de una parcela y para el dibujo
/// de una nueva.
///
/// **El zoom va con botones, no con la rueda del ratón** (petición del
/// usuario, 2026-09-22). En la ficha de la parcela el mapa está dentro de una
/// página con scroll: con la rueda activa, bajar por la página acercaba el
/// mapa en vez de moverse. En pantallas táctiles se sigue pudiendo pellizcar.
class ParcelMap extends StatefulWidget {
  const ParcelMap({
    super.key,
    required this.anillos,
    this.centro,
    this.imagen,
    this.opacidadImagen = 1,
    this.verticesEnCurso = const [],
    this.onTap,
    this.controller,
  });

  /// Contornos ya cerrados que se pintan como polígono.
  final List<List<LatLng>> anillos;

  /// Dónde encuadrar si no hay contorno todavía.
  final LatLng? centro;

  /// Imagen superpuesta (el NDVI) con sus límites geográficos.
  final ({String url, LatLngBounds bounds})? imagen;
  final double opacidadImagen;

  /// Vértices que el usuario va tocando al dibujar una parcela nueva.
  final List<LatLng> verticesEnCurso;

  final void Function(LatLng punto)? onTap;

  /// Opcional: si no se da, el mapa crea el suyo (los botones de zoom lo
  /// necesitan igualmente).
  final MapController? controller;

  @override
  State<ParcelMap> createState() => _ParcelMapState();
}

class _ParcelMapState extends State<ParcelMap> {
  late final MapController _controlador = widget.controller ?? MapController();

  void _zoom(double paso) {
    final camara = _controlador.camera;
    _controlador.move(
      camara.center,
      (camara.zoom + paso).clamp(_zoomMinimo, MapaBase.zoomMaximo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puntos = [...widget.anillos.expand((a) => a), ...widget.verticesEnCurso];
    final centroInicial =
        widget.centro ?? (puntos.isNotEmpty ? puntos.first : const LatLng(40.4, -3.7));

    return Stack(
      children: [
        FlutterMap(
          mapController: _controlador,
          options: MapOptions(
            initialCenter: centroInicial,
            initialZoom: _zoomParcela,
            minZoom: _zoomMinimo,
            maxZoom: MapaBase.zoomMaximo,
            // Todo menos la rueda: ver la documentación de la clase.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
            ),
            onTap: widget.onTap == null ? null : (_, punto) => widget.onTap!(punto),
          ),
          children: [
            TileLayer(
              urlTemplate: MapaBase.urlTeselas,
              userAgentPackageName: MapaBase.agenteUsuario,
              maxNativeZoom: MapaBase.zoomMaximo.toInt(),
            ),
            // El NDVI va entre el mapa base y el contorno: así el borde de la
            // parcela siempre se ve, por encima de la imagen.
            if (widget.imagen != null)
              Opacity(
                opacity: widget.opacidadImagen,
                child: OverlayImageLayer(
                  overlayImages: [
                    OverlayImage(
                      bounds: widget.imagen!.bounds,
                      imageProvider: NetworkImage(widget.imagen!.url),
                    ),
                  ],
                ),
              ),
            if (widget.anillos.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final anillo in widget.anillos)
                    Polygon(
                      points: anillo,
                      borderColor: AppColors.brand,
                      borderStrokeWidth: 2.5,
                      // Relleno muy tenue: tapar el NDVI con el color de marca
                      // sería esconder justo lo que se ha venido a ver.
                      color: AppColors.brand.withValues(alpha: 0.08),
                    ),
                ],
              ),
            if (widget.verticesEnCurso.isNotEmpty) ...[
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: widget.verticesEnCurso,
                    borderColor: AppColors.brand,
                    borderStrokeWidth: 2,
                    color: AppColors.brand.withValues(alpha: 0.12),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final vertice in widget.verticesEnCurso)
                    Marker(point: vertice, width: 14, height: 14, child: const _Vertice()),
                ],
              ),
            ],
            const RichAttributionWidget(
              attributions: [TextSourceAttribution(MapaBase.atribucion, onTap: null)],
            ),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: 'Acercar',
                icon: const Icon(Icons.add),
                onPressed: () => _zoom(1),
              ),
              const SizedBox(height: 4),
              IconButton.filledTonal(
                tooltip: 'Alejar',
                icon: const Icon(Icons.remove),
                onPressed: () => _zoom(-1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Vertice extends StatelessWidget {
  const _Vertice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brand,
        shape: BoxShape.circle,
        // Borde del color de superficie del tema, no un blanco a mano: se
        // distingue igual sobre la ortofoto y respeta el modo oscuro.
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
    );
  }
}
