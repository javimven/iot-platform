import '../../../core/api/api_client.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';

/// Directorio IoT global del Admin de plataforma (ADR-0005, `BACKLOG.md`
/// #18/#20) — crear, listar, editar, deshabilitar/dar de baja y rotar
/// credencial, igual que la ruta de miembro (ADR-0005 ya decidía este
/// alcance completo desde el principio).
class PlatformDirectoryApi {
  final ApiClient _client;

  PlatformDirectoryApi(this._client);

  Future<List<Installation>> installations(String organizationId) async {
    final list = await _client.getJsonList('/platform/organizations/$organizationId/installations');
    return list.map((e) => Installation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Installation> createInstallation(String organizationId, {required String name}) async {
    final json = await _client
        .postJson('/platform/organizations/$organizationId/installations', body: {'name': name});
    return Installation.fromJson(json);
  }

  Future<Installation> updateInstallation(
    String organizationId,
    String id, {
    required String name,
  }) async {
    final json = await _client.patchJson(
      '/platform/organizations/$organizationId/installations/$id',
      body: {'name': name},
    );
    return Installation.fromJson(json);
  }

  /// Baja lógica.
  Future<void> deleteInstallation(String organizationId, String id) =>
      _client.delete('/platform/organizations/$organizationId/installations/$id');

  Future<List<Zone>> zones(String organizationId, String installationId) async {
    final list = await _client.getJsonList(
      '/platform/organizations/$organizationId/installations/$installationId/zones',
    );
    return list.map((e) => Zone.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Zone> createZone(
    String organizationId,
    String installationId, {
    required String name,
  }) async {
    final json = await _client.postJson(
      '/platform/organizations/$organizationId/installations/$installationId/zones',
      body: {'name': name},
    );
    return Zone.fromJson(json);
  }

  Future<Zone> updateZone(
    String organizationId,
    String installationId,
    String id, {
    required String name,
    String? zoneType,
  }) async {
    final json = await _client.patchJson(
      '/platform/organizations/$organizationId/installations/$installationId/zones/$id',
      body: {'name': name, if (zoneType != null && zoneType.isNotEmpty) 'zoneType': zoneType},
    );
    return Zone.fromJson(json);
  }

  /// Baja lógica.
  Future<void> deleteZone(String organizationId, String installationId, String id) => _client
      .delete('/platform/organizations/$organizationId/installations/$installationId/zones/$id');

  /// `GET /platform/.../gateways` no filtra por instalación (mismo gap que
  /// la ruta de miembro, `BACKLOG.md` #13) — se filtra en cliente.
  Future<List<Gateway>> gatewaysForInstallation(String organizationId, String installationId) async {
    final list = await _client.getJsonList('/platform/organizations/$organizationId/gateways');
    return list
        .map((e) => Gateway.fromJson(e as Map<String, dynamic>))
        .where((g) => g.installationId == installationId)
        .toList();
  }

  Future<GatewayCredential> createGateway(
    String organizationId, {
    required String installationId,
    required String name,
    required String connectivityType,
  }) async {
    final json = await _client.postJson(
      '/platform/organizations/$organizationId/gateways',
      body: {'installationId': installationId, 'name': name, 'connectivityType': connectivityType},
    );
    return GatewayCredential.fromJson(json);
  }

  Future<Gateway> updateGateway(String organizationId, String id, {required String name}) async {
    final json = await _client.patchJson(
      '/platform/organizations/$organizationId/gateways/$id',
      body: {'name': name},
    );
    return Gateway.fromJson(json);
  }

  /// No es baja lógica ni física — pasa a `status: disabled`.
  Future<void> disableGateway(String organizationId, String id) =>
      _client.delete('/platform/organizations/$organizationId/gateways/$id');

  /// Revoca la credencial activa y emite una nueva — la anterior deja de
  /// servir de inmediato (API_DESIGN.md §7).
  Future<GatewayCredential> rotateGatewayCredential(String organizationId, String id) async {
    final json = await _client
        .postJson('/platform/organizations/$organizationId/gateways/$id/rotate-credential');
    return GatewayCredential.fromJson(json);
  }

  Future<List<Device>> devicesForGateway(String organizationId, String gatewayId) async {
    final list = await _client
        .getJsonList('/platform/organizations/$organizationId/gateways/$gatewayId/devices');
    return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Device> createDevice(
    String organizationId,
    String gatewayId, {
    required String zoneId,
    required String externalIdentifier,
    required String name,
  }) async {
    final json = await _client.postJson(
      '/platform/organizations/$organizationId/gateways/$gatewayId/devices',
      body: {'zoneId': zoneId, 'externalIdentifier': externalIdentifier, 'name': name},
    );
    return Device.fromJson(json);
  }

  Future<Device> updateDevice(
    String organizationId,
    String gatewayId,
    String id, {
    required String name,
    required String zoneId,
  }) async {
    final json = await _client.patchJson(
      '/platform/organizations/$organizationId/gateways/$gatewayId/devices/$id',
      body: {'name': name, 'zoneId': zoneId},
    );
    return Device.fromJson(json);
  }

  /// Deshabilitar, no borrar — mismo criterio que `disableGateway`.
  Future<void> disableDevice(String organizationId, String gatewayId, String id) => _client
      .delete('/platform/organizations/$organizationId/gateways/$gatewayId/devices/$id');

  Future<List<Sensor>> sensorsForDevice(String organizationId, String deviceId) async {
    final list = await _client
        .getJsonList('/platform/organizations/$organizationId/devices/$deviceId/sensors');
    return list.map((e) => Sensor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sensor> createSensor(
    String organizationId,
    String deviceId, {
    required String externalIdentifier,
    String? label,
  }) async {
    final json = await _client.postJson(
      '/platform/organizations/$organizationId/devices/$deviceId/sensors',
      body: {
        'externalIdentifier': externalIdentifier,
        if (label != null && label.isNotEmpty) 'label': label,
      },
    );
    return Sensor.fromJson(json);
  }

  /// Baja lógica — no hay edición de sensor en el backend (solo alta/baja).
  Future<void> deleteSensor(String organizationId, String deviceId, String id) =>
      _client.delete('/platform/organizations/$organizationId/devices/$deviceId/sensors/$id');
}
