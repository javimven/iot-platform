import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/audit_controller.dart';
import '../data/audit_models.dart';

/// Auditoría de la organización (`audit.read_full`/`audit.read_technical`,
/// `PERMISSIONS.md` §4) — las 200 entradas más recientes, sin filtro de
/// fecha ni paginación (contrato real del backend, `BACKLOG.md` #15).
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(auditLogProvider.future),
        child: entries.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Sin actividad registrada todavía.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = items[index];
                return ListTile(
                  title: Text(entry.action),
                  subtitle: Text(
                    [
                      if (entry.targetType != null) '${entry.targetType}${entry.targetId != null ? ' · ${entry.targetId}' : ''}',
                      _formatDate(entry.createdAt),
                    ].join('\n'),
                  ),
                  isThreeLine: entry.targetType != null,
                  onTap: entry.metadata != null ? () => _showMetadata(context, entry) : null,
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudo cargar la auditoría.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  void _showMetadata(BuildContext context, AuditLogEntry entry) {
    const encoder = JsonEncoder.withIndent('  ');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.action),
        content: SingleChildScrollView(
          child: SelectableText(encoder.convert(entry.metadata)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
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
