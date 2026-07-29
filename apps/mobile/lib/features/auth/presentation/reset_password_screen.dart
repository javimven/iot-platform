import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../application/auth_controller.dart';

/// Enlace de email (`APP_BASE_URL/reset-password?token=...`,
/// `auth.service.ts#resetPassword`) — el token caduca en 30 min y restablecer
/// la contraseña revoca todas las sesiones activas del usuario.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String token;

  const ResetPasswordScreen({super.key, required this.token});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
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
      await ref.read(authApiProvider).resetPassword(
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
      appBar: AppBar(title: const Text('Restablecer contraseña')),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Este enlace no es válido o le falta el token de restablecimiento.'),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => context.go('/forgot-password'),
          child: const Text('Solicitar un nuevo enlace'),
        ),
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
          const Text('Elige una nueva contraseña.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nueva contraseña'),
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
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restablecer contraseña'),
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
        const Text(
          'Contraseña restablecida. Se ha cerrado la sesión en todos los dispositivos por seguridad.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Iniciar sesión'),
        ),
      ],
    );
  }
}
