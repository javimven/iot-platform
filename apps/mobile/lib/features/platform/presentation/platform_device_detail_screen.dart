import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/platform_directory_controller.dart';

class PlatformDeviceDetailScreen extends ConsumerWidget {
  final String organizationId;
  final String deviceId;
  final String deviceName;

  const PlatformDeviceDetailScreen({
    super.key,
    required this.organizationId,
    required this.deviceId,
    required this.deviceName,
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
          FilledButton(
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
            child: const Text('Crear'),
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
