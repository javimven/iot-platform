import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_button.dart';
import '../application/auth_controller.dart';

/// Enlace de email de invitación (`APP_BASE_URL/accept-invitation?token=...`,
/// `members.service.ts#acceptInvitation`) — caduca en 7 días. Activa la
/// cuenta (`member.status: invited -> active`) fijando la contraseña inicial;
/// no inicia sesión automáticamente, el usuario entra después con sus
/// credenciales (misma pantalla de login que cualquier otro acceso).
class AcceptInvitationScreen extends ConsumerStatefulWidget {
  final String token;

  const AcceptInvitationScreen({super.key, required this.token});

  @override
  ConsumerState<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends ConsumerState<AcceptInvitationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _succeeded = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authApiProvider).acceptInvitation(
            token: widget.token,
            newPassword: _passwordController.text,
          );
      setState(() {
        _isLoading = false;
        _succeeded = true;
      });
    } on ApiException catch (error) {
      setState(() {
        _isLoading = false;
        _errorMessage = error.title;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activar cuenta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: widget.token.isEmpty
                ? _buildMissingToken(context)
                : _succeeded
                    ? _buildSuccess(context)
                    : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildMissingToken(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Este enlace de invitación no es válido o le falta el token.'),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Elige una contraseña para activar tu cuenta.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            validator: (value) => (value == null || value.length < 8)
                ? 'Mínimo 8 caracteres'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
            validator: (value) =>
                (value != _passwordController.text) ? 'Las contraseñas no coinciden' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: 'Activar cuenta',
            loading: _isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, size: 48),
        const SizedBox(height: 16),
        const Text('Cuenta activada. Ya puedes iniciar sesión.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        AppButton(
          label: 'Iniciar sesión',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
