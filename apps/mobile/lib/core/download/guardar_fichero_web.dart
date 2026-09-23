import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Descarga en el navegador: un `Blob` con los bytes que ya tenemos y un
/// enlace que se pulsa solo.
///
/// Se hace así y no abriendo la URL de la API porque la API pide el token en
/// la cabecera `Authorization`, y una descarga del navegador no la lleva. Los
/// bytes ya vienen pedidos con la sesión puesta.
///
/// El `objectURL` se libera en cuanto el navegador ha empezado la descarga;
/// si no, el fichero entero se queda en memoria hasta recargar la página.
Future<bool> guardarFichero({
  required List<int> bytes,
  required String nombre,
  required String mediaType,
}) async {
  final datos = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [datos].toJS,
    web.BlobPropertyBag(type: mediaType),
  );
  final url = web.URL.createObjectURL(blob);
  final enlace = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nombre
    ..style.display = 'none';

  web.document.body?.appendChild(enlace);
  enlace.click();
  enlace.remove();
  // Un respiro antes de soltar la URL: Safari cancela la descarga si se
  // revoca en el mismo turno del bucle de eventos.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
  return true;
}
