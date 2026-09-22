import 'package:flutter/material.dart';

import 'campaign_labels.dart';

/// Campo de fecha del cuaderno. Abre el calendario de Material (en español,
/// ver `main.dart`) y enseña la fecha escrita en largo: "18 septiembre 2026"
/// no se confunde con nada, y en el campo se lee de un vistazo.
class SelectorDeFecha extends StatelessWidget {
  const SelectorDeFecha({
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.primeraFecha,
    this.ultimaFecha,
    this.onQuitar,
    super.key,
  });

  final String etiqueta;
  final DateTime? valor;
  final void Function(DateTime fecha) onCambio;
  final DateTime? primeraFecha;
  final DateTime? ultimaFecha;

  /// Si se da, aparece una aspa para dejar la fecha vacía.
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final hoy = DateTime.now();
        final elegida = await showDatePicker(
          context: context,
          initialDate: valor ?? hoy,
          firstDate: primeraFecha ?? DateTime(hoy.year - 5),
          lastDate: ultimaFecha ?? DateTime(hoy.year + 5),
        );
        if (elegida != null) onCambio(elegida);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          suffixIcon: valor != null && onQuitar != null
              ? IconButton(
                  tooltip: 'Quitar la fecha',
                  icon: const Icon(Icons.close),
                  onPressed: onQuitar,
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          valor == null ? 'Sin fecha' : fechaLarga(valor!),
          style: valor == null
              ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Hora de un tratamiento (`HH:mm`). Opcional: el reglamento europeo la pide
/// "en su caso", y en el campo no siempre se sabe.
class SelectorDeHora extends StatelessWidget {
  const SelectorDeHora({required this.valor, required this.onCambio, super.key});

  final String? valor;
  final void Function(String? hora) onCambio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final partes = valor?.split(':');
        final elegida = await showTimePicker(
          context: context,
          initialTime: partes == null
              ? TimeOfDay.now()
              : TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1])),
        );
        if (elegida != null) {
          onCambio('${elegida.hour.toString().padLeft(2, '0')}:'
              '${elegida.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Hora (opcional)',
          suffixIcon: valor == null
              ? const Icon(Icons.schedule)
              : IconButton(
                  tooltip: 'Quitar la hora',
                  icon: const Icon(Icons.close),
                  onPressed: () => onCambio(null),
                ),
        ),
        child: Text(
          valor ?? 'Sin hora',
          style: valor == null
              ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
