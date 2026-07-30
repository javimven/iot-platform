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
    final authState = ref.watch(authControllerProvider);
    final roleCode = authState.roleCode;

    // Pista de UI (igual que el resto de la app): el control real de acceso
    // lo aplica el backend (`RequirePermission`), esto solo evita ofrecer un
    // atajo a algo que devolvería 403 (`PERMISSIONS.md` §1/§4).
    final canManageMembers = roleCode == 'org_admin';
    final canSeeOrganization = roleCode == 'org_admin';
    final canSeeAudit = roleCode == 'org_admin' || roleCode == 'technician';
    // Un usuario que además de miembro de esta organización es Admin de
    // plataforma (caso raro pero posible) no tiene otro sitio desde el que
    // llegar al panel de plataforma — su redirect de sesión lo manda aquí,
    // no a `/platform` (`app_router.dart`, solo el Admin "puro" sin
    // organización aterriza allí).
    final isPlatformAdmin = authState.isPlatformAdmin;

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
            icon: const Icon(Icons.devices_outlined),
            tooltip: 'Sesiones activas',
            onPressed: () => context.push('/sessions'),
          ),
          if (canManageMembers || canSeeOrganization || canSeeAudit || isPlatformAdmin)
            PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (route) => context.push(route),
              itemBuilder: (context) => [
                if (canManageMembers)
                  const PopupMenuItem(value: '/members', child: Text('Miembros')),
                if (canSeeOrganization)
                  const PopupMenuItem(value: '/organization', child: Text('Organización')),
                if (canSeeAudit)
                  const PopupMenuItem(value: '/audit-log', child: Text('Auditoría')),
                if (isPlatformAdmin)
                  const PopupMenuItem(value: '/platform', child: Text('Panel de plataforma')),
              ],
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
