import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/organization_controller.dart';
import '../data/organization_models.dart';

/// Perfil de la organización activa (`org.profile.read`, cualquier rol) +
/// feature flags (`org_features.read`, solo `org_admin` — `PERMISSIONS.md`
/// §14, el resto de roles recibiría 403, por eso esa sección ni se pide
/// para los demás roles).
class OrganizationSettingsScreen extends ConsumerWidget {
  const OrganizationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(organizationProfileProvider);
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canEdit = roleCode == 'org_admin';

    return Scaffold(
      appBar: AppBar(title: const Text('Organización')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(organizationProfileProvider.future),
          if (canEdit) ref.refresh(organizationFeaturesProvider.future),
        ]),
        child: ListView(
          children: [
            profile.when(
              data: (org) => _ProfileSection(org: org, canEdit: canEdit),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo cargar la organización.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            if (canEdit) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Funciones contratadas', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final features = ref.watch(organizationFeaturesProvider);
                  return features.when(
                    data: (items) => items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Sin funciones adicionales contratadas todavía.'),
                          )
                        : Column(
                            children: items
                                .map((f) => ListTile(
                                      leading: Icon(
                                        f.enabled ? Icons.check_circle_outline : Icons.lock_outline,
                                        color: f.enabled ? Colors.green : null,
                                      ),
                                      title: Text(f.featureCode),
                                      subtitle: Text(f.enabled ? 'Activa' : 'No disponible en tu plan'),
                                    ))
                                .toList(),
                          ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('No se pudieron cargar las funciones.\n$error'),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends ConsumerWidget {
  final OrganizationProfile org;
  final bool canEdit;

  const _ProfileSection({required this.org, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(org.name, style: Theme.of(context).textTheme.titleLarge),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                  onPressed: () => _showEditDialog(context, ref, org),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Email de contacto: ${org.contactEmail}'),
          const SizedBox(height: 4),
          Text('Identificador: ${org.slug}'),
          const SizedBox(height: 4),
          Text('Estado: ${org.status == 'active' ? 'Activa' : 'Suspendida'}'),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    OrganizationProfile org,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: org.name);
    final emailController = TextEditingController(text: org.contactEmail);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar organización'),
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
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email de contacto'),
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
                await ref.read(organizationApiProvider).updateProfile(
                      name: nameController.text.trim(),
                      contactEmail: emailController.text.trim(),
                    );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar.\n$error')),
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
      ref.invalidate(organizationProfileProvider);
    }
  }
}
