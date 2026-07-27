import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    if (alert.gatewayName != null) {
      return 'Gateway "${alert.gatewayName}" sin conexión';
    }
    if (alert.deviceName != null) {
      return 'Dispositivo "${alert.deviceName}" sin conexión';
    }
    return 'Sin conexión';
  }

  Color _statusColor(BuildContext context) {
    switch (alert.status) {
      case 'open':
        return Theme.of(context).colorScheme.error;
      case 'acknowledged':
        return Colors.orange;
      default:
        return Colors.green;
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

    return ListTile(
      leading: Icon(
        alert.alertType == 'threshold' ? Icons.warning_amber : Icons.wifi_off,
        color: _statusColor(context),
      ),
      title: Text(alert.installationName ?? 'Instalación desconocida'),
      subtitle: Text('$_description\nAbierta: ${timeFormat.format(alert.openedAt.toLocal())}'),
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
