import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../directory/data/directory_models.dart';
import '../../directory/presentation/directory_screen.dart'
    show showConfirmDialog, showGatewayCredentialDialog;
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
      appBar: AppBar(
        title: Text(installationName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar nombre',
            onPressed: () => _showEditInstallationDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar instalación',
            onPressed: () => _confirmDeleteInstallation(context, ref),
          ),
        ],
      ),
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
                      children: items
                          .map((z) => ListTile(
                                title: Text(z.name),
                                subtitle: z.zoneType != null ? Text(z.zoneType!) : null,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) => action == 'edit'
                                      ? _showEditZoneDialog(context, ref, z)
                                      : _confirmDeleteZone(context, ref, z),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                                  ],
                                ),
                              ))
                          .toList(),
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

  Future<void> _showEditInstallationDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: installationName);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar instalación'),
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
                    .updateInstallation(organizationId, installationId, name: nameController.text.trim());
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar la instalación.\n$error')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved == true && context.mounted) {
      ref.invalidate(platformInstallationsProvider(organizationId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instalación actualizada.')),
      );
    }
  }

  Future<void> _confirmDeleteInstallation(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar instalación',
      message: '¿Seguro que quieres eliminar "$installationName"? Esta acción es una baja lógica.',
    );
    if (!confirmed) return;
    try {
      await ref.read(platformDirectoryApiProvider).deleteInstallation(organizationId, installationId);
      ref.invalidate(platformInstallationsProvider(organizationId));
      if (context.mounted) context.pop();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la instalación.\n$error')),
        );
      }
    }
  }

  Future<void> _showEditZoneDialog(BuildContext context, WidgetRef ref, Zone zone) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: zone.name);
    final zoneTypeController = TextEditingController(text: zone.zoneType ?? '');
    final params = (organizationId: organizationId, installationId: installationId);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar zona'),
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
                controller: zoneTypeController,
                decoration: const InputDecoration(labelText: 'Tipo (opcional)'),
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
                await ref.read(platformDirectoryApiProvider).updateZone(
                      organizationId,
                      installationId,
                      zone.id,
                      name: nameController.text.trim(),
                      zoneType: zoneTypeController.text.trim(),
                    );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar la zona.\n$error')),
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
      ref.invalidate(platformZonesProvider(params));
    }
  }

  Future<void> _confirmDeleteZone(BuildContext context, WidgetRef ref, Zone zone) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar zona',
      message: '¿Seguro que quieres eliminar "${zone.name}"? Esta acción es una baja lógica.',
    );
    if (!confirmed) return;
    final params = (organizationId: organizationId, installationId: installationId);
    try {
      await ref.read(platformDirectoryApiProvider).deleteZone(organizationId, installationId, zone.id);
      ref.invalidate(platformZonesProvider(params));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la zona.\n$error')),
        );
      }
    }
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
