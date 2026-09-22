import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/campaign_models.dart';
import '../data/notebook_models.dart';
import 'campaign_labels.dart';
import 'completeness_view.dart' show textoDePendientes;
import 'selector_de_fecha.dart';

/// Cerrar una campaña: se pide la fecha de fin y, si se sabe, la producción.
/// A partir de ahí su cuaderno queda como estaba; para corregir algo, se
/// reabre, y esa reapertura queda auditada con su motivo (ADR-0012).
Future<void> cerrarCampana(BuildContext context, WidgetRef ref, Campana campana) async {
  var fin = DateTime.now();
  final produccion = TextEditingController();
  final notas = TextEditingController();

  // Lo que falta se avisa **antes** de cerrar, para poder volver atrás y
  // apuntarlo. Nunca bloquea (ADR-0013), y si la revisión falla se cierra
  // igual: no se deja a nadie sin poder cerrar su campaña por eso.
  RevisionDelCuaderno? revision;
  if (campana.resumen.esCompleta) {
    try {
      revision = await ref.read(campaignsApiProvider).revision(campana.id);
    } catch (_) {
      revision = null;
    }
  }
  if (!context.mounted) return;

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Cerrar la campaña'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Después no se podrán apuntar ni cambiar actividades sin reabrirla.'),
              if (revision != null && !revision.sinPendientes) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'En el cuaderno quedan ${textoDePendientes(revision).toLowerCase()}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Puedes cerrarla igual y completarlo luego reabriéndola; o cancelar '
                        'ahora y verlo en "Revisión".',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SelectorDeFecha(
                etiqueta: 'Fecha de fin',
                valor: fin,
                primeraFecha: campana.resumen.startDate,
                onCambio: (fecha) => setState(() => fin = fecha),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: produccion,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(
                  labelText: 'Producción final (opcional)',
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notas,
                decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cerrar campaña')),
        ],
      ),
    ),
  );
  if (confirmado != true || !context.mounted) return;

  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(campaignsApiProvider).cerrar(
          campana.id,
          endDate: fin,
          declaredProductionKg: double.tryParse(produccion.text.trim().replaceAll(',', '.')),
          closingNotes: notas.text,
        );
    refrescarCampana(ref, campana.id);
    avisos.showSnackBar(const SnackBar(content: Text('Campaña cerrada.')));
  } catch (error) {
    avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}

/// Reabrir exige un motivo: es corregir un cuaderno cerrado, y queda auditado.
Future<void> reabrirCampana(BuildContext context, WidgetRef ref, Campana campana) async {
  final motivo = TextEditingController();
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reabrir la campaña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Queda registrado quién la reabre y por qué.'),
          const SizedBox(height: 12),
          TextField(
            controller: motivo,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'Falta un tratamiento de octubre',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reabrir')),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(campaignsApiProvider).reabrir(campana.id, motivo.text);
    refrescarCampana(ref, campana.id);
    avisos.showSnackBar(const SnackBar(content: Text('Campaña reabierta.')));
  } catch (error) {
    avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}

/// Borrado lógico de una campaña viva. Una cerrada no se borra: su cuaderno
/// es historia, y el backend lo impide.
Future<void> borrarCampana(BuildContext context, WidgetRef ref, Campana campana) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Eliminar la campaña?'),
      content: Text(
        'Se elimina "${campana.resumen.name}" y todo lo registrado en ella deja de verse.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  final navegador = Navigator.of(context);
  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(campaignsApiProvider).borrar(campana.id);
    ref.invalidate(campanasProvider);
    if (navegador.canPop()) navegador.pop();
  } catch (error) {
    avisos.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}
