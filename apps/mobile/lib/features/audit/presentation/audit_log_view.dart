import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audit_models.dart';

/// Vista compartida entre la auditoría de organización (`AuditLogScreen`) y
/// la de plataforma (`PlatformAuditLogScreen`) — mismo contrato real
/// (`BACKLOG.md` #15: array plano, sin paginación) y misma presentación,
/// solo cambia de dónde viene la lista.
class AuditLogView extends StatelessWidget {
  final AsyncValue<List<AuditLogEntry>> entries;
  final Future<void> Function() onRefresh;

  const AuditLogView({super.key, required this.entries, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
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
