import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_button.dart';
import '../application/auth_controller.dart';

/// API_DESIGN.md §3: siempre responde igual (email enviado "si la cuenta
/// existe") tanto si el email está registrado como si no, para no filtrar
/// qué cuentas existen — por eso esta pantalla nunca muestra un error de
/// "email no encontrado", solo errores de red/validación de formato.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
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
      await ref.read(authApiProvider).forgotPassword(email: _emailController.text.trim());
      setState(() {
        _isLoading = false;
        _submitted = true;
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
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _submitted ? _buildConfirmation(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Introduce tu email y, si existe una cuenta asociada, te enviaremos un enlace para restablecer tu contraseña.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) =>
                (value == null || !value.contains('@')) ? 'Introduce un email válido' : null,
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
            label: 'Enviar enlace',
            loading: _isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Si existe una cuenta con ese email, recibirás un enlace para restablecer tu contraseña en unos minutos.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Volver a iniciar sesión',
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
