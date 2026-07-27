import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../readings/application/channel_type_labels.dart';
import '../application/installations_controller.dart';

/// Vista resumen de una instalación (FUNCTIONAL_REQUIREMENTS.md §12): última
/// lectura de cada canal; pulsar una lleva a su gráfica histórica
/// (`ChannelHistoryScreen`).
class InstallationDetailScreen extends ConsumerWidget {
  final String installationId;

  const InstallationDetailScreen({super.key, required this.installationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installation = ref.watch(installationProvider(installationId));
    final readings = ref.watch(latestReadingsProvider(installationId));
    final timeFormat = DateFormat('dd/MM HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: installation.when(
          data: (value) => Text(value.name),
          loading: () => const Text('Instalación'),
          error: (_, __) => const Text('Instalación'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Directorio',
            onPressed: () => context.push('/installations/$installationId/directory'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(latestReadingsProvider(installationId).future),
        child: readings.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavía no ha llegado ninguna lectura para esta instalación.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reading = items[index];
                final label = ChannelTypeLabels.labelFor(reading.channelTypeCode);
                final unit = ChannelTypeLabels.unitFor(reading.channelTypeCode);
                return ListTile(
                  title: Text(label),
                  subtitle: Text('Última medida: ${timeFormat.format(reading.tsOrigin.toLocal())}'),
                  trailing: Text(
                    '${reading.value.toStringAsFixed(1)} $unit',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => context.push(
                    '/channels/${reading.channelId}/history',
                    extra: reading.channelTypeCode,
                  ),
                );
              },
            );
          },
          error: (error, _) => Center(child: Text('No se pudieron cargar las lecturas.\n$error')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
