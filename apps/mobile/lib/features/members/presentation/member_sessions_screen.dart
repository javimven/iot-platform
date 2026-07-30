import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../directory/presentation/directory_screen.dart' show showConfirmDialog;
import '../../sessions/data/sessions_models.dart';
import '../application/members_controller.dart';

/// Sesiones activas de otro miembro (`sessions.read_others`/`revoke_others`,
/// `BACKLOG.md` #14) — a diferencia de `SessionsListScreen` (propia), aquí
/// todas las sesiones son revocables: nunca es "este dispositivo" desde el
/// punto de vista de quien administra.
class MemberSessionsScreen extends ConsumerWidget {
  final String memberId;
  final String memberName;

  const MemberSessionsScreen({super.key, required this.memberId, required this.memberName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(memberSessionsProvider(memberId));

    return Scaffold(
      appBar: AppBar(title: Text('Sesiones de $memberName')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(memberSessionsProvider(memberId).future),
        child: sessions.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Sin sesiones activas.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final session = items[index];
                return ListTile(
                  title: Text(session.userAgent ?? 'Dispositivo desconocido'),
                  subtitle: Text(
                    '${session.ipAddress ?? 'IP desconocida'}\n'
                    'Último uso: ${_formatDate(session.lastUsedAt)}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cerrar sesión',
      message: '¿Cerrar la sesión de "${session.userAgent ?? 'este dispositivo'}" de $memberName? '
          'Tendrá que iniciar sesión de nuevo.',
    );
    if (!confirmed) return;

    try {
      await ref.read(membersApiProvider).revokeSession(memberId, session.id);
      ref.invalidate(memberSessionsProvider(memberId));
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
