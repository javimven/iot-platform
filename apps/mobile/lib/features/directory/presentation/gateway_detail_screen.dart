import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_controller.dart';
import '../application/directory_controller.dart';
import '../data/directory_models.dart';
import 'directory_screen.dart' show showGatewayCredentialDialog;

class GatewayDetailScreen extends ConsumerWidget {
  final String gatewayId;

  const GatewayDetailScreen({super.key, required this.gatewayId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(gatewayProvider(gatewayId));
    final devices = ref.watch(devicesForGatewayProvider(gatewayId));
    final timeFormat = DateFormat('dd/MM HH:mm');
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canManage = roleCode == 'org_admin' || roleCode == 'technician';

    return Scaffold(
      appBar: AppBar(
        title: gateway.when(
          data: (g) => Text(g.name),
          loading: () => const Text('Gateway'),
          error: (_, __) => const Text('Gateway'),
        ),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.key),
              tooltip: 'Rotar credencial',
              onPressed: () => _rotateCredential(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(devicesForGatewayProvider(gatewayId).future),
        child: ListView(
          children: [
            gateway.when(
              data: (g) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tipo de conexión: ${g.connectivityType}'),
                    Text('Estado: ${g.status}'),
                    Text(
                      g.lastSeenAt == null
                          ? 'Sin datos de conexión todavía'
                          : 'Última conexión: ${timeFormat.format(g.lastSeenAt!.toLocal())}',
                    ),
                  ],
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo cargar el gateway.\n$error'),
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
                  const Text('Dispositivos', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (canManage)
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Nuevo dispositivo',
                      onPressed: () => _showCreateDeviceDialog(context, ref, gateway.value),
                    ),
                ],
              ),
            ),
            devices.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin dispositivos registrados.'),
                    )
                  : Column(
                      children: items
                          .map((d) => ListTile(
                                title: Text(d.name),
                                subtitle: Text(d.status),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/devices/${d.id}'),
                              ))
                          .toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar los dispositivos.\n$error'),
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

  Future<void> _rotateCredential(BuildContext context, WidgetRef ref) async {
    try {
      final credential = await ref.read(directoryApiProvider).rotateGatewayCredential(gatewayId);
      if (context.mounted) await showGatewayCredentialDialog(context, credential);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo rotar la credencial.\n$error')),
        );
      }
    }
  }

  Future<void> _showCreateDeviceDialog(
    BuildContext context,
    WidgetRef ref,
    Gateway? gateway,
  ) async {
    if (gateway == null) return;
    final zones = await ref.read(zonesForInstallationProvider(gateway.installationId).future);
    if (zones.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta instalación todavía no tiene zonas — crea una primero.'),
          ),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final identifierController = TextEditingController();
    final nameController = TextEditingController();
    var zoneId = zones.first.id;

    if (!context.mounted) return;
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
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                ),
                TextFormField(
                  controller: identifierController,
                  decoration: const InputDecoration(labelText: 'Identificador'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: zoneId,
                  decoration: const InputDecoration(labelText: 'Zona'),
                  items: zones
                      .map((z) => DropdownMenuItem(value: z.id, child: Text(z.name)))
                      .toList(),
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
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(directoryApiProvider).createDevice(
                        gatewayId,
                        zoneId: zoneId,
                        externalIdentifier: identifierController.text.trim(),
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
      ref.invalidate(devicesForGatewayProvider(gatewayId));
    }
  }
}
