import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/platform_controller.dart';

/// Editor de funciones contratadas de una organización (`org_features.update`,
/// exclusivo del Admin de plataforma, `PERMISSIONS.md` §14). Cruza el
/// catálogo completo (`GET /platform/features`, `BACKLOG.md` #17) con lo que
/// la organización ya tiene activado — sin el catálogo, una organización que
/// nunca activó nada no mostraría ninguna función que ofrecer.
class PlatformOrganizationFeaturesScreen extends ConsumerStatefulWidget {
  final String organizationId;
  final String organizationName;

  const PlatformOrganizationFeaturesScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  ConsumerState<PlatformOrganizationFeaturesScreen> createState() =>
      _PlatformOrganizationFeaturesScreenState();
}

class _PlatformOrganizationFeaturesScreenState
    extends ConsumerState<PlatformOrganizationFeaturesScreen> {
  final Map<String, bool> _pendingChanges = {};
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(platformFeatureCatalogProvider);
    final orgFeatures = ref.watch(platformOrganizationFeaturesProvider(widget.organizationId));

    return Scaffold(
      appBar: AppBar(title: Text('Funciones · ${widget.organizationName}')),
      body: catalog.when(
        data: (features) => orgFeatures.when(
          data: (enabledRows) {
            final enabledByCode = {for (final f in enabledRows) f.featureCode: f.enabled};
            return ListView(
              children: [
                for (final feature in features)
                  SwitchListTile(
                    title: Text(feature.label),
                    subtitle: Text(feature.code),
                    value: _pendingChanges[feature.code] ?? enabledByCode[feature.code] ?? false,
                    onChanged: _isSaving
                        ? null
                        : (checked) => setState(() => _pendingChanges[feature.code] = checked),
                  ),
              ],
            );
          },
          error: (error, _) => _ErrorMessage('No se pudieron cargar las funciones activas.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => _ErrorMessage('No se pudo cargar el catálogo de funciones.\n$error'),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
      floatingActionButton: _pendingChanges.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(platformApiProvider).setOrganizationFeatures(
            widget.organizationId,
            [
              for (final entry in _pendingChanges.entries)
                (featureCode: entry.key, enabled: entry.value),
            ],
          );
      ref.invalidate(platformOrganizationFeaturesProvider(widget.organizationId));
      setState(() {
        _pendingChanges.clear();
        _isSaving = false;
      });
    } catch (error) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron guardar los cambios.\n$error')),
        );
      }
    }
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;
  const _ErrorMessage(this.message);

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
