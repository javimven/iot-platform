import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../directory/presentation/directory_screen.dart' show showConfirmDialog;
import '../../installations/application/installations_controller.dart';
import '../application/members_controller.dart';
import '../data/members_models.dart';

/// Gestión de miembros de la organización (`PERMISSIONS.md` §1) — solo
/// `org_admin` tiene `members.*`, por eso el punto de entrada a esta
/// pantalla (en `InstallationsListScreen`) ya se oculta para el resto de
/// roles; aquí no hace falta repetir la comprobación en cada acción porque
/// si alguien llega sin permiso, el backend devuelve 403 en la primera
/// llamada (pista de UI, no control de acceso real, igual que el resto de
/// la app).
class MembersListScreen extends ConsumerWidget {
  const MembersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Miembros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Invitar miembro',
            onPressed: () => _showInviteDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(membersListProvider.future),
        child: members.when(
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage('Esta organización todavía no tiene miembros.');
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = items[index];
                return ListTile(
                  title: Text(member.fullName),
                  subtitle: Text(
                    '${member.email}\n${memberRoleLabel(member.roleCode)} · ${memberStatusLabel(member.status)}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _handleAction(context, ref, member, action),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'role', child: Text('Cambiar rol')),
                      const PopupMenuItem(value: 'scope', child: Text('Asignar alcance')),
                      const PopupMenuItem(value: 'sessions', child: Text('Sesiones activas')),
                      if (member.status == 'active')
                        const PopupMenuItem(value: 'suspend', child: Text('Suspender'))
                      else if (member.status == 'suspended')
                        const PopupMenuItem(value: 'reactivate', child: Text('Reactivar')),
                      const PopupMenuItem(value: 'remove', child: Text('Eliminar')),
                    ],
                  ),
                );
              },
            );
          },
          error: (error, _) => _CenteredMessage('No se pudieron cargar los miembros.\n$error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    Member member,
    String action,
  ) async {
    if (action == 'role') {
      await _showChangeRoleDialog(context, ref, member);
    } else if (action == 'scope') {
      await _showScopeDialog(context, ref, member);
    } else if (action == 'sessions') {
      context.push('/members/${member.id}/sessions', extra: member.fullName);
    } else if (action == 'suspend') {
      await _updateStatus(context, ref, member, 'suspended');
    } else if (action == 'reactivate') {
      await _updateStatus(context, ref, member, 'active');
    } else if (action == 'remove') {
      await _confirmRemove(context, ref, member);
    }
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    var roleCode = 'technician';

    final invited = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Invitar miembro'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Introduce un email válido' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: roleCode,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: memberRoleCodes
                      .map((code) => DropdownMenuItem(value: code, child: Text(memberRoleLabel(code))))
                      .toList(),
                  onChanged: (value) => setState(() => roleCode = value!),
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
                  await ref.read(membersApiProvider).invite(
                        email: emailController.text.trim(),
                        roleCode: roleCode,
                      );
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo invitar al miembro.\n$error')),
                    );
                  }
                }
              },
              child: const Text('Invitar'),
            ),
          ],
        ),
      ),
    );

    if (invited == true) {
      ref.invalidate(membersListProvider);
    }
  }

  Future<void> _showChangeRoleDialog(BuildContext context, WidgetRef ref, Member member) async {
    var roleCode = member.roleCode;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('Rol de ${member.fullName}'),
          content: DropdownButtonFormField<String>(
            initialValue: roleCode,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: memberRoleCodes
                .map((code) => DropdownMenuItem(value: code, child: Text(memberRoleLabel(code))))
                .toList(),
            onChanged: (value) => setState(() => roleCode = value!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(membersApiProvider).updateRole(member.id, roleCode: roleCode);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo cambiar el rol.\n$error')),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (changed == true) {
      ref.invalidate(membersListProvider);
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    Member member,
    String status,
  ) async {
    try {
      await ref.read(membersApiProvider).updateStatus(member.id, status: status);
      ref.invalidate(membersListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el estado.\n$error')),
        );
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, Member member) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar miembro',
      message: '¿Seguro que quieres eliminar a "${member.fullName}" de la organización?',
    );
    if (!confirmed) return;
    try {
      await ref.read(membersApiProvider).remove(member.id);
      ref.invalidate(membersListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar al miembro.\n$error')),
        );
      }
    }
  }

  Future<void> _showScopeDialog(BuildContext context, WidgetRef ref, Member member) async {
    final installations = await ref.read(installationsApiProvider).list();
    final currentScope = await ref.read(membersApiProvider).getScope(member.id);
    final selected = currentScope.toSet();
    if (!context.mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('Alcance de ${member.fullName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sin ninguna marcada, el miembro ve todas las instalaciones. '
                  'Marca solo las que debería ver.',
                ),
                const SizedBox(height: 8),
                ...installations.map(
                  (installation) => CheckboxListTile(
                    title: Text(installation.name),
                    value: selected.contains(installation.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        selected.add(installation.id);
                      } else {
                        selected.remove(installation.id);
                      }
                    }),
                  ),
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
                try {
                  await ref.read(membersApiProvider).setScope(member.id, selected.toList());
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo guardar el alcance.\n$error')),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      ref.invalidate(memberScopeProvider(member.id));
    }
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
