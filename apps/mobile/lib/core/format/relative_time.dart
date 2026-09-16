/// «Hace 3 min» en vez de una fecha: en campo se quiere saber de un vistazo si
/// el dato está al día (BACKLOG.md #49, mejora F).
String formatAgo(DateTime timestamp, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(timestamp);
  if (elapsed.inSeconds < 60) return 'hace un momento';
  if (elapsed.inMinutes < 60) return 'hace ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'hace ${elapsed.inHours} h';
  final days = elapsed.inDays;
  return days == 1 ? 'hace 1 día' : 'hace $days días';
}
