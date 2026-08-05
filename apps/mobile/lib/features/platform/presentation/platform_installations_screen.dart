import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_button.dart';
import '../application/platform_directory_controller.dart';

/// Directorio IoT global del Admin de plataforma (ADR-0005) para una
/// organización concreta — solo crear y listar (`BACKLOG.md` #20: no hay
/// edición/baja por ID disponible para el Admin de plataforma todavía).
class PlatformInstallationsScreen extends ConsumerWidget {
  final String organizationId;
  final String organizationName;

  const PlatformInstallationsScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installations = ref.watch(platformInstallationsProvider(organizationId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Directorio IoT · $organizationName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nueva instalación',
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformInstallationsProvider(organizationId).future),
        child: installations.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Esta organización todavía no tiene instalaciones.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final installation = items[index];
                return ListTile(
                  title: Text(installation.name),
                  subtitle: Text(installation.locationText ?? 'Sin ubicación registrada'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/platform/organizations/$organizationId/installations/${installation.id}',
                    extra: {'organizationName': organizationName, 'installationName': installation.name},
                  ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar las instalaciones.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva instalación'),
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
          AppButton(
            label: 'Crear',
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ref
                    .read(platformDirectoryApiProvider)
                    .createInstallation(organizationId, name: nameController.text.trim());
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo crear la instalación.\n$error')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );

    if (created == true) {
      ref.invalidate(platformInstallationsProvider(organizationId));
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
