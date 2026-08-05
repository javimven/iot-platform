import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../directory/data/directory_models.dart';
import '../../directory/presentation/directory_screen.dart' show showConfirmDialog;
import '../application/platform_directory_controller.dart';

class PlatformDeviceDetailScreen extends ConsumerWidget {
  final String organizationId;
  final String deviceId;
  final String deviceName;
  final String gatewayId;
  final String installationId;

  const PlatformDeviceDetailScreen({
    super.key,
    required this.organizationId,
    required this.deviceId,
    required this.deviceName,
    required this.gatewayId,
    required this.installationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (organizationId: organizationId, deviceId: deviceId);
    final sensors = ref.watch(platformSensorsForDeviceProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar dispositivo',
            onPressed: () => _showEditDeviceDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.block),
            tooltip: 'Deshabilitar',
            onPressed: () => _confirmDisable(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nuevo sensor',
            onPressed: () => _showCreateSensorDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformSensorsForDeviceProvider(params).future),
        child: sensors.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Sin sensores registrados.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sensor = items[index];
                return ListTile(
                  title: Text(sensor.label ?? sensor.externalIdentifier),
                  subtitle: Text(sensor.externalIdentifier),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar sensor',
                    onPressed: () => _confirmDeleteSensor(context, ref, sensor),
                  ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar los sensores.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _showEditDeviceDialog(BuildContext context, WidgetRef ref) async {
    final zones = await ref.read(
      platformZonesProvider((organizationId: organizationId, installationId: installationId)).future,
    );
    if (zones.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta instalación todavía no tiene zonas.')),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: deviceName);
    var zoneId = zones.first.id;

    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Editar dispositivo'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: zoneId,
                  decoration: const InputDecoration(labelText: 'Zona'),
                  items: [
                    for (final z in zones) DropdownMenuItem(value: z.id, child: Text(z.name)),
                  ],
                  onChanged: (value) => setState(() => zoneId = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            AppButton(
              label: 'Guardar',
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(platformDirectoryApiProvider).updateDevice(
                        organizationId,
                        gatewayId,
                        deviceId,
                        name: nameController.text.trim(),
                        zoneId: zoneId,
                      );
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo guardar el dispositivo.\n$error')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      ref.invalidate(platformDevicesForGatewayProvider((organizationId: organizationId, gatewayId: gatewayId)));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispositivo actualizado.')),
      );
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
      await ref.read(platformDirectoryApiProvider).disableDevice(organizationId, gatewayId, deviceId);
      if (context.mounted) {
        ref.invalidate(
          platformDevicesForGatewayProvider((organizationId: organizationId, gatewayId: gatewayId)),
        );
      }
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
    final params = (organizationId: organizationId, deviceId: deviceId);
    try {
      await ref.read(platformDirectoryApiProvider).deleteSensor(organizationId, deviceId, sensor.id);
      ref.invalidate(platformSensorsForDeviceProvider(params));
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
    final externalIdController = TextEditingController();
    final labelController = TextEditingController();
    final params = (organizationId: organizationId, deviceId: deviceId);

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
                controller: externalIdController,
                decoration: const InputDecoration(labelText: 'Identificador externo'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Etiqueta (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          AppButton(
            label: 'Crear',
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ref.read(platformDirectoryApiProvider).createSensor(
                      organizationId,
                      deviceId,
                      externalIdentifier: externalIdController.text.trim(),
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
          ),
        ],
      ),
    );

    if (created == true) {
      ref.invalidate(platformSensorsForDeviceProvider(params));
    }
  }
}

class _CenteredMessage extends StatelessWidget {
  final String message;
  const _CenteredMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
