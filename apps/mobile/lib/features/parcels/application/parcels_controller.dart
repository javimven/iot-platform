import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/parcel_models.dart';
import '../data/parcels_api.dart';

final parcelsApiProvider = Provider<ParcelsApi>(
  (ref) => ParcelsApi(ref.watch(apiClientProvider)),
);

/// Parcelas de una finca. `autoDispose` como el resto de listados: al salir de
/// la pantalla no interesa conservarlas.
final parcelasDeFincaProvider =
    FutureProvider.autoDispose.family<List<Parcel>, String>((ref, installationId) {
  return ref.watch(parcelsApiProvider).deInstalacion(installationId);
});

/// Finca elegida en la pantalla de satelite. Vive fuera del widget para que
/// volver atras desde el dibujo de una parcela no pierda la seleccion.
final fincaSeleccionadaProvider = StateProvider<String?>((ref) => null);

/// Parcela elegida dentro de esa finca.
final parcelaSeleccionadaProvider = StateProvider<String?>((ref) => null);
