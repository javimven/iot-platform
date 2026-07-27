import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_controller.dart';
import '../application/directory_controller.dart';

class DeviceDetailScreen extends ConsumerWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider(deviceId));
    final sensors = ref.watch(sensorsForDeviceProvider(deviceId));
    final timeFormat = DateFormat('dd/MM HH:mm');
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canManage = roleCode == 'org_admin' || roleCode == 'technician';

    return Scaffold(
      appBar: AppBar(
        title: device.when(
          data: (d) => Text(d.name),
          loading: () => const Text('Dispositivo'),
          error: (_, __) => const Text('Dispositivo'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(sensorsForDeviceProvider(deviceId).future),
        child: ListView(
          children: [
            device.when(
              data: (d) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estado: ${d.status}'),
                    Text(
                      d.lastSeenAt == null
                          ? 'Sin datos de conexión todavía'
                          : 'Última conexión: ${timeFormat.format(d.lastSeenAt!.toLocal())}',
                    ),
                  ],
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo cargar el dispositivo.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sensores', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (canManage)
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Nuevo sensor',
                      onPressed: () => _showCreateSensorDialog(context, ref),
                    ),
                ],
              ),
            ),
            sensors.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin sensores registrados.'),
                    )
                  : Column(
                      children: items
                          .map((s) => ListTile(
                                title: Text(s.label ?? s.externalIdentifier),
                                subtitle: Text(s.externalIdentifier),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/sensors/${s.id}'),
                              ))
                          .toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar los sensores.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSensorDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final identifierController = TextEditingController();
    final labelController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo sensor'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: identifierController,
                decoration: const InputDecoration(labelText: 'Identificador'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Etiqueta (opcional)'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Máximo 4 sensores por dispositivo.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ref.read(directoryApiProvider).createSensor(
                      deviceId,
                      externalIdentifier: identifierController.text.trim(),
                      label: labelController.text.trim(),
                    );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo crear el sensor.\n$error')),
                  );
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (created == true) {
      ref.invalidate(sensorsForDeviceProvider(deviceId));
    }
  }
}
