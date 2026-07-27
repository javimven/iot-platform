import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../readings/application/channel_type_labels.dart';
import '../application/directory_controller.dart';

/// Última parada del directorio (Sensor → Canales): muestra el umbral de
/// alerta configurado de cada canal (FUNCTIONAL_REQUIREMENTS.md §8-9).
/// Editar el umbral queda para un siguiente paso (README.md).
class SensorDetailScreen extends ConsumerWidget {
  final String sensorId;

  const SensorDetailScreen({super.key, required this.sensorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensor = ref.watch(sensorProvider(sensorId));
    final channels = ref.watch(channelsForSensorProvider(sensorId));

    return Scaffold(
      appBar: AppBar(
        title: sensor.when(
          data: (s) => Text(s.label ?? s.externalIdentifier),
          loading: () => const Text('Sensor'),
          error: (_, __) => const Text('Sensor'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(channelsForSensorProvider(sensorId).future),
        child: channels.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Este sensor todavía no tiene canales (se crean automáticamente '
                      'con la primera lectura válida).',
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
                final channel = items[index];
                final label = ChannelTypeLabels.labelFor(channel.channelTypeCode);
                final unit = ChannelTypeLabels.unitFor(channel.channelTypeCode);
                final hasThreshold =
                    channel.alertThresholdMin != null || channel.alertThresholdMax != null;
                return ListTile(
                  title: Text(label),
                  subtitle: Text(
                    hasThreshold
                        ? 'Umbral: ${channel.alertThresholdMin ?? '–'} a ${channel.alertThresholdMax ?? '–'} $unit'
                        : 'Sin umbral propio (usa el de la organización, si existe)',
                  ),
                );
              },
            );
          },
          error: (error, _) => Center(child: Text('No se pudieron cargar los canales.\n$error')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
