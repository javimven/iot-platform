import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/satellite_api.dart';
import '../data/satellite_models.dart';

final satelliteApiProvider = Provider<SatelliteApi>(
  (ref) => SatelliteApi(ref.watch(apiClientProvider)),
);

/// Ultima observacion utilizable de una parcela. Puede ser `null`: una parcela
/// recien creada todavia no tiene ninguna, y eso no es un error.
final ultimaObservacionProvider =
    FutureProvider.autoDispose.family<ObservacionSatelite?, String>((ref, parcelId) {
  return ref.watch(satelliteApiProvider).ultima(parcelId);
});

/// Serie de NDVI para la grafica. Se pide el ultimo ano: con revisita de unos
/// cinco dias y descartando lo nublado, son unas pocas decenas de puntos.
final serieNdviProvider =
    FutureProvider.autoDispose.family<List<PuntoSatelite>, String>((ref, parcelId) {
  final hasta = DateTime.now();
  return ref.watch(satelliteApiProvider).serie(
        parcelId,
        from: hasta.subtract(const Duration(days: 365)),
        to: hasta,
      );
});

/// Enlace firmado de la imagen que se pinta sobre el mapa. Caduca, asi que se
/// pide cada vez que se abre la parcela en vez de guardarlo.
final enlaceImagenNdviProvider = FutureProvider.autoDispose
    .family<EnlaceAsset?, ({String parcelId, ObservacionSatelite observacion})>((ref, args) async {
  final imagen = args.observacion.assets.where((a) => a.esImagenParaPintar).toList();
  if (imagen.isEmpty) {
    return null;
  }
  return ref.watch(satelliteApiProvider).enlaceDeAsset(
        parcelId: args.parcelId,
        observationId: args.observacion.observationId,
        assetId: imagen.first.assetId,
      );
});
