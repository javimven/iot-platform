import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../directory/data/directory_models.dart';
import '../application/platform_directory_controller.dart';

class PlatformGatewayDetailScreen extends ConsumerWidget {
  final String organizationId;
  final String gatewayId;
  final String gatewayName;
  final String installationId;

  const PlatformGatewayDetailScreen({
    super.key,
    required this.organizationId,
    required this.gatewayId,
    required this.gatewayName,
    required this.installationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gatewayParams = (organizationId: organizationId, gatewayId: gatewayId);
    final devices = ref.watch(platformDevicesForGatewayProvider(gatewayParams));
    final zones = ref.watch(
      platformZonesProvider((organizationId: organizationId, installationId: installationId)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(gatewayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nuevo dispositivo',
            onPressed: () => _showCreateDeviceDialog(context, ref, zones.value ?? []),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformDevicesForGatewayProvider(gatewayParams).future),
        child: devices.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Sin dispositivos registrados.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = items[index];
                return ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.status),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/platform/organizations/$organizationId/devices/${device.id}',
                    extra: device.name,
                  ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar los dispositivos.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _showCreateDeviceDialog(
    BuildContext context,
    WidgetRef ref,
    List<Zone> zones,
  ) async {
    if (zones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea antes al menos una zona en esta instalación.')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final externalIdController = TextEditingController();
    final nameController = TextEditingController();
    String? zoneId = zones.first.id;
    final gatewayParams = (organizationId: organizationId, gatewayId: gatewayId);

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Nuevo dispositivo'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: zoneId,
                  decoration: const InputDecoration(labelText: 'Zona'),
                  items: [
                    for (final z in zones) DropdownMenuItem(value: z.id, child: Text(z.name)),
                  ],
                  onChanged: (value) => setState(() => zoneId = value),
                ),
                TextFormField(
                  controller: externalIdController,
                  decoration: const InputDecoration(labelText: 'Identificador externo'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                ),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
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
                if (!formKey.currentState!.validate() || zoneId == null) return;
                try {
                  await ref.read(platformDirectoryApiProvider).createDevice(
                        organizationId,
                        gatewayId,
                        zoneId: zoneId!,
                        externalIdentifier: externalIdController.text.trim(),
                        name: nameController.text.trim(),
                      );
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo crear el dispositivo.\n$error')),
                    );
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      ref.invalidate(platformDevicesForGatewayProvider(gatewayParams));
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
