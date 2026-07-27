import '../../../core/api/api_client.dart';
import 'directory_models.dart';

class DirectoryApi {
  final ApiClient _client;

  DirectoryApi(this._client);

  Future<List<Zone>> zonesForInstallation(String installationId) async {
    final list = await _client.getJsonList('/installations/$installationId/zones');
    return list.map((e) => Zone.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Zone> createZone(String installationId, {required String name, String? zoneType}) async {
    final json = await _client.postJson(
      '/installations/$installationId/zones',
      body: {'name': name, if (zoneType != null && zoneType.isNotEmpty) 'zoneType': zoneType},
    );
    return Zone.fromJson(json);
  }

  /// `GET /gateways` no acepta filtro por instalación (backend, gap conocido
  /// — ver BACKLOG.md #13 sobre paginación/filtrado de listados); se filtra
  /// aquí porque a esta escala (≤500 dispositivos, NON_FUNCTIONAL_REQUIREMENTS.md
  /// §2) devolver todos los gateways de la organización y filtrar en cliente
  /// no es un problema de rendimiento.
  Future<List<Gateway>> gatewaysForInstallation(String installationId) async {
    final list = await _client.getJsonList('/gateways');
    return list
        .map((e) => Gateway.fromJson(e as Map<String, dynamic>))
        .where((g) => g.installationId == installationId)
        .toList();
  }

  Future<Gateway> getGateway(String id) async {
    final json = await _client.getJson('/gateways/$id');
    return Gateway.fromJson(json);
  }

  /// `GatewayCreateDto.connectivityType` (backend): `lora_concentrator`,
  /// `direct_nbiot` o `direct_other` (ADR-0004).
  Future<GatewayCredential> createGateway({
    required String installationId,
    required String name,
    required String connectivityType,
  }) async {
    final json = await _client.postJson(
      '/gateways',
      body: {'installationId': installationId, 'name': name, 'connectivityType': connectivityType},
    );
    return GatewayCredential.fromJson(json);
  }

  /// Revoca la credencial activa y emite una nueva — la anterior deja de
  /// servir de inmediato (API_DESIGN.md §7).
  Future<GatewayCredential> rotateGatewayCredential(String id) async {
    final json = await _client.postJson('/gateways/$id/rotate-credential');
    return GatewayCredential.fromJson(json);
  }

  Future<List<Device>> devicesForGateway(String gatewayId) async {
    final list = await _client.getJsonList('/gateways/$gatewayId/devices');
    return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Device> getDevice(String id) async {
    final json = await _client.getJson('/devices/$id');
    return Device.fromJson(json);
  }

  Future<Device> createDevice(
    String gatewayId, {
    required String zoneId,
    required String externalIdentifier,
    required String name,
  }) async {
    final json = await _client.postJson(
      '/gateways/$gatewayId/devices',
      body: {'zoneId': zoneId, 'externalIdentifier': externalIdentifier, 'name': name},
    );
    return Device.fromJson(json);
  }

  Future<List<Sensor>> sensorsForDevice(String deviceId) async {
    final list = await _client.getJsonList('/devices/$deviceId/sensors');
    return list.map((e) => Sensor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sensor> getSensor(String id) async {
    final json = await _client.getJson('/sensors/$id');
    return Sensor.fromJson(json);
  }

  /// Máximo 4 sensores por dispositivo (FUNCTIONAL_REQUIREMENTS.md §7) — el
  /// backend lo hace cumplir, aquí solo se informa, no se valida.
  Future<Sensor> createSensor(String deviceId, {required String externalIdentifier, String? label}) async {
    final json = await _client.postJson(
      '/devices/$deviceId/sensors',
      body: {
        'externalIdentifier': externalIdentifier,
        if (label != null && label.isNotEmpty) 'label': label,
      },
    );
    return Sensor.fromJson(json);
  }

  Future<List<Channel>> channelsForSensor(String sensorId) async {
    final list = await _client.getJsonList('/sensors/$sensorId/channels');
    return list.map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `null` en uno de los dos límites lo deja sin ese lado del umbral (usa
  /// el umbral por defecto de la organización, si existe — ChannelsService).
  Future<Channel> updateChannelThreshold(String channelId, {double? min, double? max}) async {
    final json = await _client.patchJson(
      '/channels/$channelId',
      body: {'alertThresholdMin': min, 'alertThresholdMax': max},
    );
    return Channel.fromJson(json);
  }
}
