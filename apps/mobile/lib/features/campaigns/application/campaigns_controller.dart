import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/activity_models.dart';
import '../data/campaign_models.dart';
import '../data/campaigns_api.dart';

final campaignsApiProvider = Provider<CampaignsApi>(
  (ref) => CampaignsApi(ref.watch(apiClientProvider)),
);

/// Pestaña del listado: las activas o las ya cerradas.
enum VistaDeCampanas { activas, finalizadas }

final vistaDeCampanasProvider = StateProvider<VistaDeCampanas>((ref) => VistaDeCampanas.activas);

/// Finca por la que se filtra el listado; nula = todas.
final fincaDeCampanasProvider = StateProvider<String?>((ref) => null);

final campanasProvider = FutureProvider.autoDispose<List<CampanaResumida>>((ref) {
  final vista = ref.watch(vistaDeCampanasProvider);
  final finca = ref.watch(fincaDeCampanasProvider);
  return ref.watch(campaignsApiProvider).listar(
        status: vista == VistaDeCampanas.activas ? 'active' : 'closed',
        installationId: finca,
      );
});

final campanaProvider = FutureProvider.autoDispose.family<Campana, String>((ref, id) {
  return ref.watch(campaignsApiProvider).ficha(id);
});

final actividadesProvider = FutureProvider.autoDispose.family<List<Actividad>, String>((ref, id) {
  return ref.watch(campaignsApiProvider).actividades(id);
});

final resumenCampanaProvider = FutureProvider.autoDispose.family<ResumenCampana, String>((ref, id) {
  return ref.watch(campaignsApiProvider).resumen(id);
});

/// El catálogo es pequeño y no cambia mientras se usa la app: se pide una vez.
final cultivosProvider = FutureProvider<List<CultivoCatalogo>>((ref) {
  return ref.watch(campaignsApiProvider).cultivos();
});

/// Tras registrar, corregir o borrar algo, todo lo que lo enseña se vuelve a
/// pedir: la línea de tiempo, el resumen, la cabecera y el listado.
void refrescarCampana(WidgetRef ref, String campaignId) {
  ref.invalidate(campanaProvider(campaignId));
  ref.invalidate(actividadesProvider(campaignId));
  ref.invalidate(resumenCampanaProvider(campaignId));
  ref.invalidate(campanasProvider);
}

/// Qué puede hacer cada rol (PERMISSIONS.md §14 ter). Es cosmético: el backend
/// lo comprueba igual. Sirve para no enseñar botones que acabarían en un 403.
class PermisosDeCampana {
  const PermisosDeCampana(this.roleCode);

  final String? roleCode;

  bool get puedeCrear => roleCode == 'org_admin' || roleCode == 'technician';
  bool get puedeCerrar => puedeCrear;
  bool get puedeRegistrar => roleCode != null && roleCode != 'read_only';
  bool get puedeBorrar => roleCode == 'org_admin';
}

final permisosDeCampanaProvider = Provider<PermisosDeCampana>(
  (ref) => PermisosDeCampana(ref.watch(authControllerProvider).roleCode),
);
