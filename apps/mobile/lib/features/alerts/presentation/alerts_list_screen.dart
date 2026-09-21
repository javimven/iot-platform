import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../../readings/application/channel_type_labels.dart';
import '../application/alerts_controller.dart';
import '../data/alert_models.dart';

/// Lista de alertas (FUNCTIONAL_REQUIREMENTS.md §15): filtro por estado,
/// reconocer/resolver. El backend ya impone quién puede hacer qué
/// (`alerts.acknowledge`/`alerts.resolve`, PERMISSIONS.md) — el rol solo se
/// usa aquí para no mostrar botones que el servidor rechazaría, nunca como
/// control de acceso real (nunca confiar solo en el frontend).
class AlertsListScreen extends ConsumerWidget {
  const AlertsListScreen({super.key});

  static const _statusFilters = <String?, String>{
    'open': 'Abiertas',
    'acknowledged': 'Reconocidas',
    'resolved': 'Resueltas',
    null: 'Todas',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsListProvider);
    final selectedFilter = ref.watch(alertStatusFilterProvider);
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canAct = roleCode != 'read_only';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          PopupMenuButton<String?>(
            initialValue: selectedFilter,
            onSelected: (value) => ref.read(alertStatusFilterProvider.notifier).state = value,
            itemBuilder: (context) => _statusFilters.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(alertsListProvider.future),
        child: alerts.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay alertas para este filtro.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _AlertTile(alert: items[index], canAct: canAct),
            );
          },
          error: (error, _) => Center(child: Text('No se pudieron cargar las alertas.\n$error')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  final Alert alert;
  final bool canAct;

  const _AlertTile({required this.alert, required this.canAct});

  String get _description {
    if (alert.alertType == 'threshold') {
      final label = ChannelTypeLabels.labelFor(alert.channelTypeCode ?? '');
      final value = alert.details?['value'];
      return value == null ? '$label fuera de rango' : '$label fuera de rango (valor: $value)';
    }
    if (alert.alertType == 'no_sensor_data') {
      // La estación sigue en línea: lo que falla son las lecturas. En la
      // WSC2-N suele ser un reinicio que le borra las declaraciones de sus
      // sensores RS485, y entonces hay que ir con el cable de consola.
      final nombre = alert.gatewayName;
      return nombre == null
          ? 'Sin datos de sensores desde hace más de una hora'
          : 'La estación "$nombre" lleva más de una hora sin datos de sus sensores';
    }
    if (alert.gatewayName != null) {
      return 'Gateway "${alert.gatewayName}" sin conexión';
    }
    if (alert.deviceName != null) {
      return 'Dispositivo "${alert.deviceName}" sin conexión';
    }
    return 'Sin conexión';
  }

  IconData get _icono {
    switch (alert.alertType) {
      case 'threshold':
        return Icons.warning_amber;
      case 'no_sensor_data':
        return Icons.sensors_off;
      default:
        return Icons.wifi_off;
    }
  }

  ({String label, AppStatusTone tone}) get _statusChip {
    switch (alert.status) {
      case 'open':
        return (label: 'Abierta', tone: AppStatusTone.critical);
      case 'acknowledged':
        return (label: 'Reconocida', tone: AppStatusTone.warn);
      default:
        return (label: 'Resuelta', tone: AppStatusTone.ok);
    }
  }

  Future<void> _act(
    WidgetRef ref,
    BuildContext context,
    Future<void> Function(String id) action,
  ) async {
    try {
      await action(alert.id);
      ref.invalidate(alertsListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la alerta.\n$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = DateFormat('dd/MM HH:mm');
    final api = ref.read(alertsApiProvider);

    final status = _statusChip;

    return ListTile(
      leading: Icon(_icono),
      title: Text(alert.installationName ?? 'Instalación desconocida'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_description\nAbierta: ${timeFormat.format(alert.openedAt.toLocal())}'),
          const SizedBox(height: 4),
          StatusChip(label: status.label, tone: status.tone),
        ],
      ),
      isThreeLine: true,
      trailing: canAct && alert.status != 'resolved'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (alert.status == 'open')
                  IconButton(
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Reconocer',
                    onPressed: () => _act(ref, context, api.acknowledge),
                  ),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: 'Resolver',
                  onPressed: () => _act(ref, context, api.resolve),
                ),
              ],
            )
          : null,
    );
  }
}
