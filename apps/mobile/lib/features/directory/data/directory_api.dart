import '../../../core/api/api_client.dart';
import 'directory_models.dart';

class DirectoryApi {
  final ApiClient _client;

  DirectoryApi(this._client);

  Future<List<Zone>> zonesForInstallation(String installationId) async {
    final list = await _client.getJsonList('/installations/$installationId/zones');
    return list.map((e) => Zone.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<List<Device>> devicesForGateway(String gatewayId) async {
    final list = await _client.getJsonList('/gateways/$gatewayId/devices');
    return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Device> getDevice(String id) async {
    final json = await _client.getJson('/devices/$id');
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

  Future<List<Channel>> channelsForSensor(String sensorId) async {
    final list = await _client.getJsonList('/sensors/$sensorId/channels');
    return list.map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
