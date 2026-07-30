import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/sessions_controller.dart';
import '../data/sessions_models.dart';

/// Sesiones activas del propio usuario (`sessions.read_own`/`revoke_own`,
/// `PERMISSIONS.md` §1) — revocar la sesión de *este mismo* dispositivo se
/// deshabilita aquí (ya existe el botón "Cerrar sesión" para eso en la
/// barra de Instalaciones); esta pantalla es para cerrar sesión en **otros**
/// dispositivos (p. ej. un móvil perdido).
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsListProvider);
    final currentSessionId = ref.watch(authControllerProvider).refreshSessionId;

    return Scaffold(
      appBar: AppBar(title: const Text('Sesiones activas')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(sessionsListProvider.future),
        child: sessions.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('No hay sesiones activas.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final session = items[index];
                final isCurrent = session.id == currentSessionId;
                return ListTile(
                  title: Text(session.userAgent ?? 'Dispositivo desconocido'),
                  subtitle: Text(
                    '${session.ipAddress ?? 'IP desconocida'}\n'
                    'Último uso: ${_formatDate(session.lastUsedAt)}',
                  ),
                  isThreeLine: true,
                  trailing: isCurrent
                      ? const Chip(label: Text('Este dispositivo'))
                      : IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Cerrar esta sesión',
                          onPressed: () => _confirmRevoke(context, ref, session),
                        ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar las sesiones.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref, UserSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: Text(
          '¿Cerrar la sesión de "${session.userAgent ?? 'este dispositivo'}"? '
          'Tendrá que iniciar sesión de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sessionsApiProvider).revoke(session.id);
      ref.invalidate(sessionsListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar la sesión.\n$error')),
        );
      }
    }
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
