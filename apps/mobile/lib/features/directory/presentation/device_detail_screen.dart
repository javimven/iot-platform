import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_controller.dart';
import '../application/directory_controller.dart';
import '../data/directory_models.dart';
import 'directory_screen.dart' show showConfirmDialog;

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
        actions: [
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar nombre',
              onPressed: () => _showEditDeviceDialog(context, ref, device.value),
            ),
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: 'Deshabilitar',
              onPressed: () => _confirmDisable(context, ref),
            ),
          ],
        ],
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
                                onTap: () => context.push('/sensors/${s.id}'),
                                trailing: canManage
                                    ? IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Eliminar sensor',
                                        onPressed: () => _confirmDeleteSensor(context, ref, s),
                                      )
                                    : const Icon(Icons.chevron_right),
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

  Future<void> _showEditDeviceDialog(BuildContext context, WidgetRef ref, Device? device) async {
    if (device == null) return;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: device.name);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar dispositivo'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
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
                await ref
                    .read(directoryApiProvider)
                    .updateDevice(deviceId, name: nameController.text.trim());
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar el dispositivo.\n$error')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved == true) {
      ref.invalidate(deviceProvider(deviceId));
    }
  }

  Future<void> _confirmDisable(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Deshabilitar dispositivo',
      message: 'Dejará de aceptar telemetría hasta que se vuelva a habilitar.',
    );
    if (!confirmed) return;
    try {
      await ref.read(directoryApiProvider).disableDevice(deviceId);
      ref.invalidate(deviceProvider(deviceId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo deshabilitar el dispositivo.\n$error')),
        );
      }
    }
  }

  Future<void> _confirmDeleteSensor(BuildContext context, WidgetRef ref, Sensor sensor) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar sensor',
      message:
          '¿Seguro que quieres eliminar "${sensor.label ?? sensor.externalIdentifier}"? '
          'Esta acción es una baja lógica.',
    );
    if (!confirmed) return;
    try {
      await ref.read(directoryApiProvider).deleteSensor(sensor.id);
      ref.invalidate(sensorsForDeviceProvider(deviceId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar el sensor.\n$error')),
        );
      }
    }
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
