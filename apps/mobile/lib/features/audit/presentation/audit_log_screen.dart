import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/audit_controller.dart';
import 'audit_log_view.dart';

/// Auditoría de la organización (`audit.read_full`/`audit.read_technical`,
/// `PERMISSIONS.md` §4) — las 200 entradas más recientes, sin filtro de
/// fecha ni paginación (contrato real del backend, `BACKLOG.md` #15).
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: AuditLogView(
        entries: ref.watch(auditLogProvider),
        onRefresh: () => ref.refresh(auditLogProvider.future),
      ),
    );
  }
}
