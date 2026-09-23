import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/guardar_fichero.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import 'campaign_labels.dart';

/// Exportar el cuaderno (BACKLOG.md #60, fase 7). Cuatro salidas, y la
/// diferencia entre las dos primeras importa lo suficiente como para
/// explicarla en una línea cada una: el informe es para leerlo y enseñarlo; el
/// del cuaderno de explotación va en el orden de sus apartados, para cotejarlo
/// con quien lo pida.
class _Salida {
  const _Salida({
    required this.titulo,
    required this.detalle,
    required this.icono,
    required this.formato,
    this.layout,
  });

  final String titulo;
  final String detalle;
  final IconData icono;
  final String formato;
  final String? layout;
}

const _salidas = [
  _Salida(
    titulo: 'Informe en PDF',
    detalle: 'Para leerlo o imprimirlo: el resumen primero y el detalle después.',
    icono: Icons.description_outlined,
    formato: 'pdf',
    layout: 'informe',
  ),
  _Salida(
    titulo: 'PDF con los apartados del cuaderno de explotación',
    detalle: 'Los mismos datos en el orden del Cuaderno Único de Explotación.',
    icono: Icons.rule_folder_outlined,
    formato: 'pdf',
    layout: 'cue',
  ),
  _Salida(
    titulo: 'Hoja de cálculo (CSV)',
    detalle: 'Una fila por actividad para abrirla en Excel, con coma decimal.',
    icono: Icons.table_chart_outlined,
    formato: 'csv',
  ),
  _Salida(
    titulo: 'Datos completos (JSON)',
    detalle: 'Todo el cuaderno tal cual, para otro programa o para tu técnico.',
    icono: Icons.data_object_outlined,
    formato: 'json',
  ),
];

Future<void> exportarCuaderno(BuildContext context, WidgetRef ref, Campana campana) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _HojaDeExportar(campana: campana),
  );
}

class _HojaDeExportar extends ConsumerStatefulWidget {
  const _HojaDeExportar({required this.campana});

  final Campana campana;

  @override
  ConsumerState<_HojaDeExportar> createState() => _HojaDeExportarState();
}

class _HojaDeExportarState extends ConsumerState<_HojaDeExportar> {
  String? _generando;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exportar el cuaderno', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.campana.resumen.estaCerrada
                  ? 'La campaña está cerrada: se exporta tal como quedó al cerrarla.'
                  : 'Se exporta lo registrado hasta hoy.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final salida in _salidas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _generando == _clave(salida)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(salida.icono),
                title: Text(salida.titulo, style: theme.textTheme.bodyLarge),
                subtitle: Text(salida.detalle, style: theme.textTheme.bodySmall),
                enabled: _generando == null,
                onTap: () => _exportar(salida),
              ),
            if (!kIsWeb) ...[
              const SizedBox(height: 4),
              Text(
                'Desde el móvil todavía no se puede guardar el fichero; ábrelo desde el '
                'ordenador y se descarga solo.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _clave(_Salida salida) => '${salida.formato}-${salida.layout ?? ''}';

  Future<void> _exportar(_Salida salida) async {
    setState(() {
      _generando = _clave(salida);
      _error = null;
    });
    final avisos = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    try {
      final fichero = await ref.read(campaignsApiProvider).exportar(
            widget.campana.id,
            formato: salida.formato,
            layout: salida.layout,
          );
      final guardado = await guardarFichero(
        bytes: fichero.bytes,
        // El nombre lo pone el servidor; si faltara, uno razonable.
        nombre: fichero.nombre ?? 'Cuaderno - ${widget.campana.resumen.name}.${salida.formato}',
        mediaType: fichero.mediaType,
      );
      if (!mounted) return;
      if (guardado) {
        navegador.pop();
        avisos.showSnackBar(const SnackBar(content: Text('Cuaderno descargado.')));
      } else {
        setState(() {
          _generando = null;
          _error = 'El cuaderno se ha generado, pero desde el móvil todavía no hay dónde '
              'guardarlo. Descárgalo desde el ordenador.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _generando = null;
          _error = mensajeDeError(error);
        });
      }
    }
  }
}
