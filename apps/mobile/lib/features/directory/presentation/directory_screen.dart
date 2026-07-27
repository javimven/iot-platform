import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../application/directory_controller.dart';
import '../data/directory_models.dart';

/// Directorio IoT de una instalación (FUNCTIONAL_REQUIREMENTS.md §4-6):
/// zonas y gateways, con alta de ambos. El botón de alta solo se muestra si
/// el rol lo permitiría (pista de UI, nunca control de acceso real — el
/// backend ya lo exige vía `zones.create`/`gateways.create`).
class DirectoryScreen extends ConsumerWidget {
  final String installationId;

  const DirectoryScreen({super.key, required this.installationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesForInstallationProvider(installationId));
    final gateways = ref.watch(gatewaysForInstallationProvider(installationId));
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canManage = roleCode == 'org_admin' || roleCode == 'technician';

    return Scaffold(
      appBar: AppBar(title: const Text('Directorio')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(zonesForInstallationProvider(installationId).future),
          ref.refresh(gatewaysForInstallationProvider(installationId).future),
        ]),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Zonas', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (canManage)
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
                  if (canManage)
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
                                onTap: () => context.push('/gateways/${g.id}'),
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
    final zoneTypeController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva zona'),
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
                await ref.read(directoryApiProvider).createZone(
                      installationId,
                      name: nameController.text.trim(),
                      zoneType: zoneTypeController.text.trim(),
                    );
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
      ref.invalidate(zonesForInstallationProvider(installationId));
    }
  }

  Future<void> _showCreateGatewayDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    var connectivityType = 'lora_concentrator';

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
                    DropdownMenuItem(
                      value: 'lora_concentrator',
                      child: Text('Concentrador LoRa'),
                    ),
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
                  final result = await ref.read(directoryApiProvider).createGateway(
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
      ref.invalidate(gatewaysForInstallationProvider(installationId));
      if (context.mounted) await showGatewayCredentialDialog(context, credential);
    }
  }
}

/// Muestra la credencial una única vez (SECURITY.md §6) — no se puede
/// recuperar después, solo rotar. Se reutiliza tras crear y tras rotar.
Future<void> showGatewayCredentialDialog(BuildContext context, GatewayCredential credential) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Credencial del gateway'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Copia esta credencial ahora — no se volverá a mostrar. '
            'Si la pierdes, tendrás que rotarla para obtener una nueva.',
          ),
          const SizedBox(height: 16),
          SelectableText('Usuario: ${credential.credentialUsername}'),
          SelectableText('Secreto: ${credential.credentialSecret}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: '${credential.credentialUsername}\n${credential.credentialSecret}',
            ),
          ),
          child: const Text('Copiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ya la he copiado'),
        ),
      ],
    ),
  );
}
