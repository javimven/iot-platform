import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../application/directory_controller.dart';

class DeviceDetailScreen extends ConsumerWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider(deviceId));
    final sensors = ref.watch(sensorsForDeviceProvider(deviceId));
    final timeFormat = DateFormat('dd/MM HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: device.when(
          data: (d) => Text(d.name),
          loading: () => const Text('Dispositivo'),
          error: (_, __) => const Text('Dispositivo'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(sensorsForDeviceProvider(deviceId).future),
        child: ListView(
          children: [
            device.when(
              data: (d) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estado: ${d.status}'),
                    Text(
                      d.lastSeenAt == null
                          ? 'Sin datos de conexión todavía'
                          : 'Última conexión: ${timeFormat.format(d.lastSeenAt!.toLocal())}',
                    ),
                  ],
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo cargar el dispositivo.\n$error'),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Sensores', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            sensors.when(
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Sin sensores registrados.'),
                    )
                  : Column(
                      children: items
                          .map((s) => ListTile(
                                title: Text(s.label ?? s.externalIdentifier),
                                subtitle: Text(s.externalIdentifier),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/sensors/${s.id}'),
                              ))
                          .toList(),
                    ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('No se pudieron cargar los sensores.\n$error'),
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
