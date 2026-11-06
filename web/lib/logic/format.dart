// Small date/number formatting helpers (no intl dependency).

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String fmtDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String fmtDateTime(DateTime d) => '${fmtDate(d)}, ${fmtTime(d)}';

/// "today 14:00", "tomorrow 09:00", "yesterday 18:30" or "Fri 13 Nov, 14:00".
String describeDue(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = (day.difference(today).inHours / 24).round();
  if (diff == 0) return 'today ${fmtTime(due)}';
  if (diff == 1) return 'tomorrow ${fmtTime(due)}';
  if (diff == -1) return 'yesterday ${fmtTime(due)}';
  return fmtDateTime(due);
}

/// 45 -> "45 min", 90 -> "1 h 30 min", 120 -> "2 h".
String fmtMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// 6.0 -> "6", 4.5 -> "4.5".
String fmtHours(double hours) =>
    hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toStringAsFixed(1);
