import '../../../core/widgets/status_chip.dart';

/// Etiqueta + tono de [StatusChip] para `Gateway.status` (`not_provisioned`/
/// `online`/`offline`/`disabled`, MQTT_PROTOCOL.md §8 — ya calculado por el
/// backend vía LWT + timeout, nunca se recalcula en el cliente). Mismo
/// patrón que `AlertsListScreen._statusChip` para el ciclo de vida de una
/// alerta.
class GatewayStatusLabels {
  static (String label, AppStatusTone tone) forStatus(String status) => switch (status) {
        'online' => ('En línea', AppStatusTone.ok),
        'offline' => ('Sin conexión', AppStatusTone.critical),
        'disabled' => ('Deshabilitada', AppStatusTone.neutral),
        _ => ('Sin aprovisionar', AppStatusTone.neutral), // 'not_provisioned'
      };
}
