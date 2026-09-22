import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../application/ubicacion_dispositivo.dart';
import 'buscador_mapa.dart';

/// Proveedor del mapa base. Separado de la librería a propósito (ADR-0011):
/// una cosa es con qué se dibuja y otra de dónde salen las teselas.
///
/// Por defecto, la **ortofoto PNOA del Instituto Geográfico Nacional**
/// (máxima actualidad, 25-50 cm por píxel). Para mirar un cultivo, una foto
/// aérea vale mucho más que un callejero: el usuario reconoce su parcela por
/// la forma del campo y los caminos, no por el nombre de la calle. Pidió el
/// cambio el usuario al ver el mapa de OpenStreetMap (2026-09-22).
///
/// Encima, una **capa de nombres y carreteras** (IGN Base Orto: teselas
/// transparentes con pueblos, carreteras y calles), que se puede apagar.
/// También la pidió el usuario: con la foto sola se reconoce la parcela, pero
/// no se sabe dónde se está para ir a buscarla.
///
/// Licencias comprobadas: acceso libre también para uso comercial,
/// compatible con CC BY 4.0 (Orden FOM/2807/2015), **con las atribuciones
/// obligatorias** que van en [atribucion] y [atribucionNombres]. Cubren solo
/// España. Los dos servidores mandan `Access-Control-Allow-Origin: *`, así
/// que funcionan también en la web.
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

  /// Nombres y carreteras sobre la foto. PNG transparente, mismos niveles que
  /// la ortofoto (comprobado hasta el 20; el 21 da 400).
  static const urlNombres = 'https://www.ign.es/wmts/ign-base?request=GetTile&service=WMTS'
      '&VERSION=1.0.0&Layer=IGNBaseOrto&Style=default'
      '&Format=image/png&TileMatrixSet=GoogleMapsCompatible'
      '&TileMatrix={z}&TileRow={y}&TileCol={x}';

  /// La que declara el propio servicio (`AccessConstraints` de su
  /// GetCapabilities).
  static const atribucionNombres = 'IGN Base · CC BY 4.0 scne.es';

  /// Último nivel con imagen en el servicio del IGN (comprobado: el 21 da 400).
  /// Pasar de ahí sería pedir teselas que no existen.
  static const zoomMaximo = 20.0;

  static const agenteUsuario = 'com.jmvsoluciones.iot_platform';
}

/// Zoom al que se ve una parcela de unas hectáreas entera en pantalla, cuando
/// no hay contorno con el que encuadrar.
const _zoomParcela = 16.0;
const _zoomMinimo = 5.0;

/// Sin contorno ni centro: España entera, para buscar desde ahí.
const _centroEspana = LatLng(40.2, -3.7);
const _zoomEspana = 6.0;

/// Al encuadrar una parcela, no acercarse más que esto: una de media hectárea
/// llenaría la pantalla y se perdería lo que tiene alrededor.
const _zoomMaximoEncuadre = 18.0;

/// Mapa de una parcela: el contorno, una imagen georreferenciada encima si la
/// hay, y los vértices mientras se dibuja.
///
/// Es tonto a propósito: no sabe de NDVI ni de observaciones, solo pinta lo
/// que le den. Así sirve igual para la ficha de una parcela y para el dibujo
/// de una nueva.
///
/// **Zoom con la rueda y, además, con botones + y −** para ajustar de nivel en
/// nivel. Hubo una versión intermedia sin rueda, y el usuario la pidió de
/// vuelta (2026-09-22): los botones eran para afinar, no para sustituirla. En
/// pantallas táctiles, pellizcar.
///
/// Con [buscador], además: caja de búsqueda (sitios y coordenadas) y botón de
/// "mi ubicación". Es lo que hace falta para encontrar dónde dibujar; en la
/// ficha de una parcela ya dibujada sobra y quita sitio a un mapa pequeño.
///
/// Consecuencia conocida: en la ficha de la parcela, con el ratón encima del
/// mapa, la rueda acerca el mapa en vez de bajar la página. Para bajar hay que
/// sacar el cursor del mapa.
class ParcelMap extends ConsumerStatefulWidget {
  const ParcelMap({
    super.key,
    required this.anillos,
    this.centro,
    this.imagen,
    this.opacidadImagen = 1,
    this.verticesEnCurso = const [],
    this.onTap,
    this.controller,
    this.buscador = false,
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

  final bool buscador;

  @override
  ConsumerState<ParcelMap> createState() => _ParcelMapState();
}

class _ParcelMapState extends ConsumerState<ParcelMap> {
  late final MapController _controlador = widget.controller ?? MapController();

  bool _nombres = true;
  bool _localizando = false;
  PosicionDispositivo? _miPosicion;
  LatLng? _puntoBuscado;

  List<LatLng> get _contorno => widget.anillos.expand((a) => a).toList();

  CameraFit get _encuadreParcela => CameraFit.coordinates(
        coordinates: _contorno,
        padding: const EdgeInsets.all(32),
        maxZoom: _zoomMaximoEncuadre,
      );

  void _zoom(double paso) {
    final camara = _controlador.camera;
    _controlador.move(
      camara.center,
      (camara.zoom + paso).clamp(_zoomMinimo, MapaBase.zoomMaximo),
    );
  }

  void _irA(LatLng punto, double zoom) {
    _controlador.move(punto, zoom.clamp(_zoomMinimo, MapaBase.zoomMaximo));
  }

  Future<void> _irAMiUbicacion() async {
    final avisos = ScaffoldMessenger.maybeOf(context);
    setState(() => _localizando = true);
    try {
      final posicion = await ref.read(ubicacionDelDispositivoProvider).actual();
      if (!mounted) return;
      setState(() {
        _miPosicion = posicion;
        _localizando = false;
      });
      _irA(posicion.punto, posicion.zoom);
      if (posicion.esAproximada) {
        avisos?.showSnackBar(
          SnackBar(
            content: Text(
              'Ubicación aproximada (± ${_distancia(posicion.precisionMetros)}). En un ordenador '
              'suele salir de la red, no de un GPS: sirve para acercarse, no para dibujar.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _localizando = false);
      avisos?.showSnackBar(
        SnackBar(
          content: Text(
            error is UbicacionNoDisponible ? error.mensaje : 'No se pudo obtener tu ubicación.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contorno = _contorno;
    final hayContorno = contorno.isNotEmpty;
    final centroInicial = widget.centro ??
        (widget.verticesEnCurso.isNotEmpty ? widget.verticesEnCurso.first : _centroEspana);
    final zoomInicial =
        widget.centro == null && widget.verticesEnCurso.isEmpty ? _zoomEspana : _zoomParcela;

    return Stack(
      children: [
        FlutterMap(
          mapController: _controlador,
          options: MapOptions(
            initialCenter: centroInicial,
            initialZoom: zoomInicial,
            // Con contorno, la parcela entera y un poco de alrededor, sea del
            // tamaño que sea (antes: zoom fijo, y una parcela pequeña salía
            // diminuta).
            initialCameraFit: hayContorno ? _encuadreParcela : null,
            minZoom: _zoomMinimo,
            maxZoom: MapaBase.zoomMaximo,
            // Rueda incluida: ver la documentación de la clase.
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            onTap: widget.onTap == null ? null : (_, punto) => widget.onTap!(punto),
          ),
          children: [
            TileLayer(
              urlTemplate: MapaBase.urlTeselas,
              userAgentPackageName: MapaBase.agenteUsuario,
              maxNativeZoom: MapaBase.zoomMaximo.toInt(),
            ),
            if (_nombres)
              TileLayer(
                key: const ValueKey('capa-nombres'),
                urlTemplate: MapaBase.urlNombres,
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
                      // Píxeles nítidos, sin suavizar. La imagen trae uno por
                      // cada 10 m, y difuminada parecía tener más detalle del
                      // que tiene y ensuciaba los bordes: no se veía qué
                      // píxeles quedaban fuera de la parcela (2026-09-22).
                      filterQuality: FilterQuality.none,
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
            if (_miPosicion != null) ...[
              // Círculo de incertidumbre: en un ordenador puede ser de
              // kilómetros, y hay que verlo para no fiarse del punto.
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _miPosicion!.punto,
                    radius: _miPosicion!.precisionMetros,
                    useRadiusInMeter: true,
                    color: AppColors.mapaMiPosicion.withValues(alpha: 0.15),
                    borderColor: AppColors.mapaMiPosicion.withValues(alpha: 0.6),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    key: const ValueKey('mi-posicion'),
                    point: _miPosicion!.punto,
                    width: 18,
                    height: 18,
                    child: const _PuntoMiPosicion(),
                  ),
                ],
              ),
            ],
            if (_puntoBuscado != null)
              MarkerLayer(
                markers: [
                  Marker(
                    key: const ValueKey('punto-buscado'),
                    point: _puntoBuscado!,
                    width: 36,
                    height: 36,
                    // La punta de la chincheta, no su centro, es el sitio.
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      size: 36,
                      color: AppColors.mapaPuntoBuscado,
                      shadows: [Shadow(color: AppColors.mapaContornoMarca, blurRadius: 3)],
                    ),
                  ),
                ],
              ),
            RichAttributionWidget(
              attributions: [
                const TextSourceAttribution(MapaBase.atribucion, onTap: null),
                if (_nombres) const TextSourceAttribution(MapaBase.atribucionNombres, onTap: null),
              ],
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
              const SizedBox(height: 12),
              if (hayContorno) ...[
                IconButton.filledTonal(
                  tooltip: 'Volver a la parcela',
                  icon: const Icon(Icons.center_focus_strong_outlined),
                  onPressed: () => _controlador.fitCamera(_encuadreParcela),
                ),
                const SizedBox(height: 4),
              ],
              if (widget.buscador) ...[
                IconButton.filledTonal(
                  tooltip: 'Mi ubicación',
                  icon: _localizando
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  onPressed: _localizando ? null : _irAMiUbicacion,
                ),
                const SizedBox(height: 4),
              ],
              IconButton.filledTonal(
                tooltip: _nombres ? 'Ocultar nombres y carreteras' : 'Mostrar nombres y carreteras',
                isSelected: _nombres,
                icon: const Icon(Icons.layers_clear_outlined),
                selectedIcon: const Icon(Icons.layers_outlined),
                onPressed: () => setState(() => _nombres = !_nombres),
              ),
            ],
          ),
        ),
        if (widget.buscador)
          Positioned(
            top: 8,
            left: 8,
            // Hueco a la derecha para la columna de botones.
            right: 64,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: BuscadorMapa(
                  onElegido: (punto, zoom) {
                    setState(() => _puntoBuscado = punto);
                    _irA(punto, zoom);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _distancia(double metros) =>
    metros >= 1000 ? '${(metros / 1000).toStringAsFixed(1)} km' : '${metros.round()} m';

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

class _PuntoMiPosicion extends StatelessWidget {
  const _PuntoMiPosicion();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.mapaMiPosicion,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.mapaContornoMarca, width: 3),
      ),
    );
  }
}
