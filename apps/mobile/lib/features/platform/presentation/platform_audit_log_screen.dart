import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/presentation/audit_log_view.dart';
import '../application/platform_controller.dart';

/// Auditoría de plataforma (`platform.audit.read`) — altas/bajas/suspensiones
/// de organización, las 200 entradas más recientes (mismo contrato real que
/// la auditoría de organización, `BACKLOG.md` #15).
class PlatformAuditLogScreen extends ConsumerWidget {
  const PlatformAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría de plataforma')),
      body: AuditLogView(
        entries: ref.watch(platformAuditLogProvider),
        onRefresh: () => ref.refresh(platformAuditLogProvider.future),
      ),
    );
  }
}
