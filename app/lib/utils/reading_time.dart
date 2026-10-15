String readingTime(DateTime? timestamp) {
  if (timestamp == null) return 'No readings yet';
  final local = timestamp.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, $hour:$minute:$second $period';
}

String readingAge(DateTime? timestamp) {
  if (timestamp == null) return 'No readings yet';
  final minutes = DateTime.now().difference(timestamp).inMinutes;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  return readingTime(timestamp);
}
