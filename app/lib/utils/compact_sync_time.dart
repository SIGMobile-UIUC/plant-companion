/// Presentation only: never changes persisted packet time or health.
String compactSyncTime(DateTime timestamp, DateTime now) {
  final elapsed = now.difference(timestamp);
  if (elapsed < const Duration(minutes: 1)) return 'Just now';
  if (elapsed < const Duration(hours: 1)) return '${elapsed.inMinutes} min ago';
  if (elapsed < const Duration(hours: 24)) {
    return '${elapsed.inHours} ${elapsed.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  final local = timestamp.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '${two(local.month)}/${two(local.day)}/${two(local.year % 100)} $hour:${two(local.minute)} ${local.hour < 12 ? 'AM' : 'PM'}';
}
