/// Shared time-formatting helpers used across chat / dashboard.
///
/// Centralised so a future format change (e.g. 24-hour mode) only needs to
/// be applied once and stays consistent across screens.
class TimeFormatter {
  const TimeFormatter._();

  /// `h:mm AM/PM` — used inside chat bubbles.
  static String formatLocalTime(DateTime dt) {
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$m $p';
  }

  /// Friendly relative timestamp for chat list rows:
  ///   today → `h:mm AM/PM`
  ///   yesterday → `Yesterday`
  ///   < 7 days → weekday short name
  ///   else → `M/D/YY`
  static String formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(that).inDays;
    if (diffDays == 0) return formatLocalTime(dt);
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) {
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return wd[dt.weekday - 1];
    }
    return '${dt.month}/${dt.day}/${dt.year % 100}';
  }
}
