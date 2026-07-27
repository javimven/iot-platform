import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/directory_controller.dart';

/// Directorio IoT de una instalación (FUNCTIONAL_REQUIREMENTS.md §4-6):
/// zonas y gateways. Solo lectura por ahora — alta/edición/baja quedan para
/// un siguiente paso (README.md).
class DirectoryScreen extends ConsumerWidget {
  final String installationId;

  const DirectoryScreen({super.key, required this.installationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesForInstallationProvider(installationId));
    final gateways = ref.watch(gatewaysForInstallationProvider(installationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Directorio')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(zonesForInstallationProvider(installationId).future),
          ref.refresh(gatewaysForInstallationProvider(installationId).future),
        ]),
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Zonas', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Gateways', style: TextStyle(fontWeight: FontWeight.bold)),
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
}
