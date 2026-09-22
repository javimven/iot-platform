import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';

/// Proveedor del mapa base. Separado de la librería a propósito (ADR-0011):
/// una cosa es con qué se dibuja y otra de dónde salen las teselas.
///
/// El valor por defecto es OpenStreetMap, que sirve para desarrollo pero **no**
/// para producción: su política de uso no ampara un SaaS. Antes de abrir esto
/// a clientes hay que poner un proveedor con licencia para ello —y a poder ser
/// con ortofoto, que para mirar un cultivo vale mucho más que un callejero—
/// vía `--dart-define`.
class MapaBase {
  static const urlTeselas = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const atribucion = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap',
  );

  /// Sin esto, OSM rechaza las peticiones de clientes que no se identifican.
  static const agenteUsuario = 'com.jmvsoluciones.iot_platform';
}

/// Zoom al que se ve una parcela de unas hectáreas entera en pantalla.
const _zoomParcela = 16.0;

/// Mapa de una parcela: el contorno, una imagen georreferenciada encima si la
/// hay, y los vértices mientras se dibuja.
///
/// Es tonto a propósito: no sabe de NDVI ni de observaciones, solo pinta lo
/// que le den. Así sirve igual para la ficha de una parcela y para el dibujo
/// de una nueva.
class ParcelMap extends StatelessWidget {
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
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final puntos = [...anillos.expand((a) => a), ...verticesEnCurso];
    final centroInicial = centro ?? (puntos.isNotEmpty ? puntos.first : const LatLng(40.4, -3.7));

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: centroInicial,
        initialZoom: _zoomParcela,
        onTap: onTap == null ? null : (_, punto) => onTap!(punto),
      ),
      children: [
        TileLayer(
          urlTemplate: MapaBase.urlTeselas,
          userAgentPackageName: MapaBase.agenteUsuario,
        ),
        // El NDVI va entre el mapa base y el contorno: así el borde de la
        // parcela siempre se ve, por encima de la imagen.
        if (imagen != null)
          Opacity(
            opacity: opacidadImagen,
            child: OverlayImageLayer(
              overlayImages: [
                OverlayImage(bounds: imagen!.bounds, imageProvider: NetworkImage(imagen!.url)),
              ],
            ),
          ),
        if (anillos.isNotEmpty)
          PolygonLayer(
            polygons: [
              for (final anillo in anillos)
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
        if (verticesEnCurso.isNotEmpty) ...[
          PolygonLayer(
            polygons: [
              Polygon(
                points: verticesEnCurso,
                borderColor: AppColors.brand,
                borderStrokeWidth: 2,
                color: AppColors.brand.withValues(alpha: 0.12),
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final vertice in verticesEnCurso)
                Marker(
                  point: vertice,
                  width: 14,
                  height: 14,
                  child: const _Vertice(),
                ),
            ],
          ),
        ],
        const RichAttributionWidget(
          attributions: [TextSourceAttribution(MapaBase.atribucion, onTap: null)],
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
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
