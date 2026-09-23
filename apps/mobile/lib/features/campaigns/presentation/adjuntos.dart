import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../application/campaigns_controller.dart';
import '../data/document_models.dart';
import 'campaign_labels.dart';

/// Fotos y documentos de una actividad o de la campaña (BACKLOG.md #60, fase
/// 6). Una tira de miniaturas y un botón: hacer la foto del albarán en el
/// momento es lo que más se usa, así que la cámara está a un toque.
class Adjuntos extends ConsumerStatefulWidget {
  const Adjuntos({
    required this.campaignId,
    this.activityId,
    this.sePuedeTocar = true,
    super.key,
  });

  final String campaignId;

  /// Nulo = los de la campaña, no los de una actividad.
  final String? activityId;
  final bool sePuedeTocar;

  @override
  ConsumerState<Adjuntos> createState() => _AdjuntosState();
}

class _AdjuntosState extends ConsumerState<Adjuntos> {
  bool _subiendo = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final documentos = ref.watch(documentosProvider(widget.campaignId));
    final theme = Theme.of(context);

    final mios = documentos.maybeWhen(
      data: (lista) => lista.where((d) => d.activityId == widget.activityId).toList(),
      orElse: () => const <DocumentoDelCuaderno>[],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos y documentos', style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        if (mios.isEmpty && !widget.sePuedeTocar)
          Text('Sin adjuntos', style: theme.textTheme.bodySmall)
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: mios.length + (widget.sePuedeTocar ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == mios.length) {
                  return _BotonDeAdjuntar(subiendo: _subiendo, onElegir: _elegir);
                }
                return _Miniatura(
                  documento: mios[i],
                  onTap: () => verDocumento(context, mios[i]),
                  onQuitar: widget.sePuedeTocar ? () => _quitar(mios[i]) : null,
                );
              },
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Future<void> _elegir() async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Hacer una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir del carrete'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;
    await _subir(origen);
  }

  Future<void> _subir(ImageSource origen) async {
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      // Se reduce antes de subir: una foto de 12 MP son varios megas y lo que
      // hace falta es que se lea el albarán, no imprimirlo en A3.
      final elegida = await ImagePicker().pickImage(
        source: origen,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (elegida == null) {
        setState(() => _subiendo = false);
        return;
      }
      final bytes = await elegida.readAsBytes();
      await ref.read(campaignsApiProvider).adjuntar(
            widget.campaignId,
            activityId: widget.activityId,
            bytes: bytes,
            filename: elegida.name,
          );
      ref.invalidate(documentosProvider(widget.campaignId));
      if (mounted) setState(() => _subiendo = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _subiendo = false;
          _error = mensajeDeError(error);
        });
      }
    }
  }

  Future<void> _quitar(DocumentoDelCuaderno documento) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar el adjunto?'),
        content: Text(
          'Se quita "${documento.nombre}" de aquí. Si está en otro sitio del cuaderno, allí se queda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await ref.read(campaignsApiProvider).quitarDocumento(
            widget.campaignId,
            documento.id,
            activityId: widget.activityId,
          );
      ref.invalidate(documentosProvider(widget.campaignId));
    } catch (error) {
      if (mounted) setState(() => _error = mensajeDeError(error));
    }
  }
}

class _BotonDeAdjuntar extends StatelessWidget {
  const _BotonDeAdjuntar({required this.subiendo, required this.onElegir});

  final bool subiendo;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 96,
      child: AppCard(
        padding: const EdgeInsets.all(8),
        onTap: subiendo ? null : onElegir,
        child: Center(
          child: subiendo
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.primary),
                    const SizedBox(height: 4),
                    Text('Añadir', style: theme.textTheme.labelSmall),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.documento, required this.onTap, this.onQuitar});

  final DocumentoDelCuaderno documento;
  final VoidCallback onTap;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 96,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppCard(
              padding: EdgeInsets.zero,
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: documento.esImagen
                    ? Image.network(
                        documento.url,
                        fit: BoxFit.cover,
                        width: 96,
                        height: 96,
                        // Un enlace caducado o sin red no puede dejar la ficha
                        // rota: se enseña el icono del tipo.
                        errorBuilder: (_, __, ___) => _SinVistaPrevia(documento: documento),
                      )
                    : _SinVistaPrevia(documento: documento),
              ),
            ),
          ),
          if (onQuitar != null)
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onQuitar,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SinVistaPrevia extends StatelessWidget {
  const _SinVistaPrevia({required this.documento});

  final DocumentoDelCuaderno documento;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            documento.mediaType == 'application/pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.insert_drive_file_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              etiquetaDeDocumento(documento.documentType),
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// El documento a tamaño completo. Una imagen se ve aquí; de un PDF se enseña
/// su ficha, porque abrirlo es cosa del sistema.
Future<void> verDocumento(BuildContext context, DocumentoDelCuaderno documento) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(documento.nombre, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${etiquetaDeDocumento(documento.documentType)} · '
              '${tamanoLegible(documento.byteSize)} · ${fechaCorta(documento.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (documento.esImagen)
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    documento.url,
                    errorBuilder: (_, __, ___) => Text(
                      'No se pudo cargar la imagen. Cierra y vuelve a abrir la campaña: '
                      'el enlace caduca por seguridad.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              )
            else
              Text(
                'Este documento no es una imagen; se guarda en el cuaderno y se descarga '
                'desde el ordenador.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Cerrar',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
