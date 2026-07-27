import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../application/installations_controller.dart';

class InstallationsListScreen extends ConsumerWidget {
  const InstallationsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installations = ref.watch(installationsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Instalaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Alertas',
            onPressed: () => context.push('/alerts'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(installationsListProvider.future),
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
                  onTap: () => context.push('/installations/${installation.id}'),
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
