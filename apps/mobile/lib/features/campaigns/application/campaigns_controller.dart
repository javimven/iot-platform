import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/activity_models.dart';
import '../data/campaign_models.dart';
import '../data/campaigns_api.dart';
import '../data/notebook_models.dart';

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

/// Lo que falta en el cuaderno de una campaña (fase 5). En una campaña
/// sencilla la respuesta viene con `aplica: false` y no se enseña nada.
final revisionDelCuadernoProvider =
    FutureProvider.autoDispose.family<RevisionDelCuaderno, String>((ref, id) {
  return ref.watch(campaignsApiProvider).revision(id);
});

/// Los catálogos del cuaderno. Se piden una vez y se rehacen al cambiarlos:
/// son listas cortas que se eligen muchas veces.
final personasDelCuadernoProvider = FutureProvider<List<PersonaCuaderno>>((ref) {
  return ref.watch(campaignsApiProvider).personas();
});

final equiposDelCuadernoProvider = FutureProvider<List<EquipoCuaderno>>((ref) {
  return ref.watch(campaignsApiProvider).equipos();
});

void refrescarCatalogos(WidgetRef ref) {
  ref.invalidate(personasDelCuadernoProvider);
  ref.invalidate(equiposDelCuadernoProvider);
}

/// Tras registrar, corregir o borrar algo, todo lo que lo enseña se vuelve a
/// pedir: la línea de tiempo, el resumen, la revisión, la cabecera y el listado.
void refrescarCampana(WidgetRef ref, String campaignId) {
  ref.invalidate(campanaProvider(campaignId));
  ref.invalidate(actividadesProvider(campaignId));
  ref.invalidate(resumenCampanaProvider(campaignId));
  ref.invalidate(revisionDelCuadernoProvider(campaignId));
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
