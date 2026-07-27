import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../readings/application/channel_type_labels.dart';
import '../application/directory_controller.dart';
import '../data/directory_models.dart';

/// Última parada del directorio (Sensor → Canales): muestra el umbral de
/// alerta configurado de cada canal (FUNCTIONAL_REQUIREMENTS.md §8-9) y
/// permite editarlo (`channels.update_threshold`).
class SensorDetailScreen extends ConsumerWidget {
  final String sensorId;

  const SensorDetailScreen({super.key, required this.sensorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensor = ref.watch(sensorProvider(sensorId));
    final channels = ref.watch(channelsForSensorProvider(sensorId));
    final roleCode = ref.watch(authControllerProvider).roleCode;
    final canManage = roleCode == 'org_admin' || roleCode == 'technician';

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
                  trailing: canManage ? const Icon(Icons.edit_outlined) : null,
                  onTap: canManage ? () => _showEditThresholdDialog(context, ref, channel) : null,
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

  Future<void> _showEditThresholdDialog(
    BuildContext context,
    WidgetRef ref,
    Channel channel,
  ) async {
    final formKey = GlobalKey<FormState>();
    final minController =
        TextEditingController(text: channel.alertThresholdMin?.toString() ?? '');
    final maxController =
        TextEditingController(text: channel.alertThresholdMax?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Umbral de alerta'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Deja un campo en blanco para no fijar ese límite (se usará el '
                'de la organización, si existe).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextFormField(
                controller: minController,
                decoration: const InputDecoration(labelText: 'Mínimo'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null)
                    ? 'Número inválido'
                    : null,
              ),
              TextFormField(
                controller: maxController,
                decoration: const InputDecoration(labelText: 'Máximo'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null)
                    ? 'Número inválido'
                    : null,
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
                await ref.read(directoryApiProvider).updateChannelThreshold(
                      channel.id,
                      min: minController.text.isEmpty ? null : double.parse(minController.text),
                      max: maxController.text.isEmpty ? null : double.parse(maxController.text),
                    );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar el umbral.\n$error')),
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
      ref.invalidate(channelsForSensorProvider(sensorId));
    }
  }
}
