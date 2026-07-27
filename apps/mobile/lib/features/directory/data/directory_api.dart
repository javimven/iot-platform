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

  Future<Zone> updateZone(String id, {required String name, String? zoneType}) async {
    final json = await _client.patchJson(
      '/zones/$id',
      body: {'name': name, if (zoneType != null && zoneType.isNotEmpty) 'zoneType': zoneType},
    );
    return Zone.fromJson(json);
  }

  /// Baja lógica (FUNCTIONAL_REQUIREMENTS.md §4) — no física.
  Future<void> deleteZone(String id) => _client.delete('/zones/$id');

  Future<Zone> getZone(String id) async {
    final json = await _client.getJson('/zones/$id');
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

  Future<Gateway> updateGateway(String id, {required String name}) async {
    final json = await _client.patchJson('/gateways/$id', body: {'name': name});
    return Gateway.fromJson(json);
  }

  /// No es baja lógica ni física — pasa a `status: disabled` (deja de
  /// aceptar tráfico MQTT) pero permanece visible (DATA_MODEL.md §4).
  Future<void> disableGateway(String id) => _client.delete('/gateways/$id');

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

  Future<Device> updateDevice(String id, {required String name, required String zoneId}) async {
    final json = await _client.patchJson('/devices/$id', body: {'name': name, 'zoneId': zoneId});
    return Device.fromJson(json);
  }

  /// Deshabilitar, no borrar — mismo criterio que `disableGateway`.
  Future<void> disableDevice(String id) => _client.delete('/devices/$id');

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

  /// Baja lógica — no hay edición de sensor en el backend (solo
  /// alta/baja), a diferencia de zona/gateway/dispositivo.
  Future<void> deleteSensor(String id) => _client.delete('/sensors/$id');

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
