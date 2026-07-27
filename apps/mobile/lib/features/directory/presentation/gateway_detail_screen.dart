import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../application/directory_controller.dart';

class GatewayDetailScreen extends ConsumerWidget {
  final String gatewayId;

  const GatewayDetailScreen({super.key, required this.gatewayId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(gatewayProvider(gatewayId));
    final devices = ref.watch(devicesForGatewayProvider(gatewayId));
    final timeFormat = DateFormat('dd/MM HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: gateway.when(
          data: (g) => Text(g.name),
          loading: () => const Text('Gateway'),
          error: (_, __) => const Text('Gateway'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(devicesForGatewayProvider(gatewayId).future),
        child: ListView(
          children: [
            gateway.when(
              data: (g) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tipo de conexión: ${g.connectivityType}'),
                    Text('Estado: ${g.status}'),
                    Text(
                      g.lastSeenAt == null
                          ? 'Sin datos de conexión todavía'
                          : 'Última conexión: ${timeFormat.format(g.lastSeenAt!.toLocal())}',
                    ),
                  ],
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo cargar el gateway.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Dispositivos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            devices.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin dispositivos registrados.'),
                    )
                  : Column(
                      children: items
                          .map((d) => ListTile(
                                title: Text(d.name),
                                subtitle: Text(d.status),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/devices/${d.id}'),
                              ))
                          .toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar los dispositivos.\n$error'),
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
