import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../directory/data/directory_models.dart';
import '../../directory/presentation/directory_screen.dart' show showGatewayCredentialDialog;
import '../application/platform_directory_controller.dart';

class PlatformInstallationDetailScreen extends ConsumerWidget {
  final String organizationId;
  final String installationId;
  final String installationName;

  const PlatformInstallationDetailScreen({
    super.key,
    required this.organizationId,
    required this.installationId,
    required this.installationName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (organizationId: organizationId, installationId: installationId);
    final zones = ref.watch(platformZonesProvider(params));
    final gateways = ref.watch(platformGatewaysForInstallationProvider(params));

    return Scaffold(
      appBar: AppBar(title: Text(installationName)),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(platformZonesProvider(params).future),
          ref.refresh(platformGatewaysForInstallationProvider(params).future),
        ]),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Zonas', style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nueva zona',
                    onPressed: () => _showCreateZoneDialog(context, ref),
                  ),
                ],
              ),
            ),
            zones.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin zonas registradas.'),
                    )
                  : Column(
                      children:
                          items.map((z) => ListTile(title: Text(z.name), subtitle: z.zoneType != null ? Text(z.zoneType!) : null)).toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar las zonas.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gateways', style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nuevo gateway',
                    onPressed: () => _showCreateGatewayDialog(context, ref),
                  ),
                ],
              ),
            ),
            gateways.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin gateways registrados.'),
                    )
                  : Column(
                      children: items
                          .map((g) => ListTile(
                                title: Text(g.name),
                                subtitle: Text('${g.connectivityType} · ${g.status}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                  '/platform/organizations/$organizationId/gateways/${g.id}',
                                  extra: {
                                    'gatewayName': g.name,
                                    'installationId': installationId,
                                  },
                                ),
                              ))
                          .toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar los gateways.\n$error'),
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

  Future<void> _showCreateZoneDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final params = (organizationId: organizationId, installationId: installationId);

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva zona'),
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
                    .read(platformDirectoryApiProvider)
                    .createZone(organizationId, installationId, name: nameController.text.trim());
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo crear la zona.\n$error')),
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
      ref.invalidate(platformZonesProvider(params));
    }
  }

  Future<void> _showCreateGatewayDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    var connectivityType = 'lora_concentrator';
    final params = (organizationId: organizationId, installationId: installationId);

    final credential = await showDialog<GatewayCredential>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Nuevo gateway'),
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
                  initialValue: connectivityType,
                  decoration: const InputDecoration(labelText: 'Tipo de conexión'),
                  items: const [
                    DropdownMenuItem(value: 'lora_concentrator', child: Text('Concentrador LoRa')),
                    DropdownMenuItem(value: 'direct_nbiot', child: Text('NB-IoT directo')),
                    DropdownMenuItem(value: 'direct_other', child: Text('Otra conexión directa')),
                  ],
                  onChanged: (value) => setState(() => connectivityType = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final result = await ref.read(platformDirectoryApiProvider).createGateway(
                        organizationId,
                        installationId: installationId,
                        name: nameController.text.trim(),
                        connectivityType: connectivityType,
                      );
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(result);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo crear el gateway.\n$error')),
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

    if (credential != null) {
      ref.invalidate(platformGatewaysForInstallationProvider(params));
      if (context.mounted) await showGatewayCredentialDialog(context, credential);
    }
  }
}
