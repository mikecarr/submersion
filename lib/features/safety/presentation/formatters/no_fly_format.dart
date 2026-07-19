/// Remaining-time label shared by the safety hub and the dashboard alerts
/// banner. Mirrors the app's duration convention (see
/// `dive_field_formatter.dart`): "Xh Ym" once there is at least an hour left,
/// "Ymin" for a minutes-only remainder.
String formatNoFlyRemaining(Duration remaining) {
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  if (hours == 0) return '${minutes}min';
  return '${hours}h ${minutes}m';
}
