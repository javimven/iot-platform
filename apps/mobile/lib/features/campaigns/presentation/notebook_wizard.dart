import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import '../data/notebook_models.dart';
import 'campaign_labels.dart';

/// El cuestionario del cuaderno completo (ADR-0013): **solo lo que la
/// plataforma no puede deducir**. La finca, el cultivo, la superficie y las
/// parcelas ya se saben y no se vuelven a preguntar.
///
/// Es una lista para marcar, no un examen: sin marcar significa "no lo hago",
/// que es una respuesta, y se puede cambiar cuando se quiera. De lo marcado
/// depende qué apartados pide el cuaderno después.
Future<Map<String, bool>?> preguntarCuestionarioDelCuaderno(
  BuildContext context, {
  Map<String, dynamic> respuestasActuales = const {},
  String textoDelBoton = 'Guardar',
}) {
  return Navigator.of(context).push<Map<String, bool>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CuestionarioScreen(
        respuestasActuales: respuestasActuales,
        textoDelBoton: textoDelBoton,
      ),
    ),
  );
}

/// "Pasar a cuaderno completo": el mismo modelo, otro modo (ADR-0013). No se
/// copia ni se borra nada, y lo ya apuntado sigue valiendo.
Future<void> pasarACuadernoCompleto(BuildContext context, WidgetRef ref, Campana campana) async {
  final respuestas = await preguntarCuestionarioDelCuaderno(
    context,
    respuestasActuales: campana.notebookProfile,
    textoDelBoton: 'Pasar a cuaderno completo',
  );
  if (respuestas == null || !context.mounted) return;

  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(campaignsApiProvider).completarCuaderno(campana.id, respuestas);
    refrescarCampana(ref, campana.id);
    avisos.showSnackBar(
      const SnackBar(content: Text('Ahora es un cuaderno de campo completo.')),
    );
  } catch (error) {
    avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}

/// Cambiar las respuestas de una campaña que ya lleva cuaderno completo.
Future<void> cambiarCuestionario(BuildContext context, WidgetRef ref, Campana campana) async {
  final respuestas = await preguntarCuestionarioDelCuaderno(
    context,
    respuestasActuales: campana.notebookProfile,
  );
  if (respuestas == null || !context.mounted) return;

  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(campaignsApiProvider).guardarPerfil(campana.id, respuestas);
    refrescarCampana(ref, campana.id);
  } catch (error) {
    avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}

class _CuestionarioScreen extends StatefulWidget {
  const _CuestionarioScreen({required this.respuestasActuales, required this.textoDelBoton});

  final Map<String, dynamic> respuestasActuales;
  final String textoDelBoton;

  @override
  State<_CuestionarioScreen> createState() => _CuestionarioScreenState();
}

class _CuestionarioScreenState extends State<_CuestionarioScreen> {
  late final Map<String, bool> _respuestas = {
    for (final pregunta in preguntasDelCuaderno)
      pregunta.clave: widget.respuestasActuales[pregunta.clave] as bool? ?? false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cuaderno de campo completo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Marca lo que hagas en esta campaña', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Con esto el cuaderno te pide solo lo que te toca. Lo que ya sabemos '
                  '—la finca, el cultivo, las parcelas y su superficie— no se pregunta. '
                  'Puedes cambiarlo cuando quieras.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final pregunta in preguntasDelCuaderno)
            SwitchListTile(
              value: _respuestas[pregunta.clave] ?? false,
              title: Text(pregunta.pregunta, style: theme.textTheme.bodyLarge),
              subtitle: Text(pregunta.detalle, style: theme.textTheme.bodySmall),
              contentPadding: EdgeInsets.zero,
              onChanged: (valor) => setState(() => _respuestas[pregunta.clave] = valor),
            ),
          const SizedBox(height: 16),
          AppButton(
            label: widget.textoDelBoton,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_respuestas),
          ),
          const SizedBox(height: 12),
          Text(
            'El cuaderno completo no bloquea nada: puedes apuntar una actividad en segundos '
            'y rellenar el resto después. Lo que falte se ve en "Revisión".',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
