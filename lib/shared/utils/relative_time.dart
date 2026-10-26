/// Tiny relative-time formatter (no external dependency).
String formatRelative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} Min${diff.inMinutes == 1 ? '' : 's'} Ago';
  if (diff.inHours < 24) return '${diff.inHours} Hour${diff.inHours == 1 ? '' : 's'} Ago';
  if (diff.inDays < 7) return '${diff.inDays} Day${diff.inDays == 1 ? '' : 's'} Ago';
  return '${time.day}/${time.month}/${time.year}';
}

String formatClockTime(DateTime time) {
  final hours = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final am = time.hour < 12 ? 'AM' : 'PM';
  return '$hours.$minute $am';
}
