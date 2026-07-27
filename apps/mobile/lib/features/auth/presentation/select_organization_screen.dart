import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

/// API_DESIGN.md §3: se muestra cuando el usuario tiene más de una
/// membresía activa — nunca se emite un token completo antes de este paso.
class SelectOrganizationScreen extends ConsumerWidget {
  const SelectOrganizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final organizations = authState.organizations;

    return Scaffold(
      appBar: AppBar(title: const Text('Elige una organización')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: organizations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final org = organizations[index];
          return ListTile(
            title: Text(org.name),
            subtitle: Text(org.roleCode),
            trailing: authState.isLoading ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
            onTap: authState.isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).selectOrganization(org.organizationId),
          );
        },
      ),
    );
  }
}
