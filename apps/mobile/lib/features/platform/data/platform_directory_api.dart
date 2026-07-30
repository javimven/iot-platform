import '../../../core/api/api_client.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';

/// Directorio IoT global del Admin de plataforma (ADR-0005, `BACKLOG.md`
/// #18) — solo crear y listar, no editar/deshabilitar: las operaciones por
/// ID solo existen en la ruta de miembro, que exige una organización propia
/// que un Admin de plataforma "puro" no tiene (`BACKLOG.md` #20, sin
/// decidir todavía). Una vez creado, el equipo de la propia organización
/// cliente gestiona el día a día desde su Directorio IoT normal.
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
}
