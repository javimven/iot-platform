/// Guardar un fichero que llega de la API (el cuaderno exportado, fase 7 del
/// #60). En el navegador se descarga; en el móvil todavía no hay dónde
/// dejarlo, así que devuelve `false` y la pantalla lo explica en vez de
/// simular que ha pasado algo.
Future<bool> guardarFichero({
  required List<int> bytes,
  required String nombre,
  required String mediaType,
}) async {
  return false;
}
