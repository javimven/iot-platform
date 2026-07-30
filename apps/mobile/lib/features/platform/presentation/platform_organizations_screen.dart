import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../organization/data/organization_models.dart';
import '../application/platform_controller.dart';

/// Panel de plataforma (`PERMISSIONS.md` §3) — alta/baja/suspensión de
/// organizaciones. Punto de entrada para un Admin de plataforma "puro" (sin
/// organización propia); ver `app_router.dart` para el redirect.
class PlatformOrganizationsScreen extends ConsumerWidget {
  const PlatformOrganizationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizations = ref.watch(platformOrganizationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Auditoría de plataforma',
            onPressed: () => context.push('/platform/audit-log'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nueva organización',
            onPressed: () => _showCreateDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformOrganizationsProvider.future),
        child: organizations.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Todavía no hay organizaciones.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final org = items[index];
                return ListTile(
                  title: Text(org.name),
                  subtitle: Text('${org.slug} · ${org.status == 'active' ? 'Activa' : 'Suspendida'}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _handleAction(context, ref, org, action),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'features', child: Text('Funciones contratadas')),
                      if (org.status == 'active')
                        const PopupMenuItem(value: 'suspend', child: Text('Suspender'))
                      else
                        const PopupMenuItem(value: 'reactivate', child: Text('Reactivar')),
                    ],
                  ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar las organizaciones.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, OrganizationProfile org, String action) {
    if (action == 'features') {
      context.push('/platform/organizations/${org.id}/features', extra: org.name);
    } else if (action == 'suspend') {
      _confirmStatusChange(context, ref, org, suspend: true);
    } else if (action == 'reactivate') {
      _confirmStatusChange(context, ref, org, suspend: false);
    }
  }

  Future<void> _confirmStatusChange(
    BuildContext context,
    WidgetRef ref,
    OrganizationProfile org, {
    required bool suspend,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(suspend ? 'Suspender organización' : 'Reactivar organización'),
        content: Text(
          suspend
              ? '¿Suspender "${org.name}"? Sus miembros no podrán acceder hasta reactivarla.'
              : '¿Reactivar "${org.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(suspend ? 'Suspender' : 'Reactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (suspend) {
        await ref.read(platformApiProvider).suspendOrganization(org.id);
      } else {
        await ref.read(platformApiProvider).reactivateOrganization(org.id);
      }
      ref.invalidate(platformOrganizationsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el estado.\n$error')),
        );
      }
    }
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final contactEmailController = TextEditingController();
    final firstAdminEmailController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva organización'),
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
                controller: contactEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email de contacto'),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Introduce un email válido' : null,
              ),
              TextFormField(
                controller: firstAdminEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email del primer administrador'),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Introduce un email válido' : null,
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
                await ref.read(platformApiProvider).createOrganization(
                      name: nameController.text.trim(),
                      contactEmail: contactEmailController.text.trim(),
                      firstAdminEmail: firstAdminEmailController.text.trim(),
                    );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo crear la organización.\n$error')),
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
      ref.invalidate(platformOrganizationsProvider);
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
