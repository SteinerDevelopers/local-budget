/// Day-group heading text (design §2.1). Pure and locale-independent on
/// purpose for E1 — `Today`/`Yesterday`, else `Wed 29 Oct`. i18n of these
/// strings is deferred (decision 1: English UI first).
abstract final class DayLabel {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String of(DateTime day, {DateTime? today}) {
    final t = today ?? DateTime.now();
    final d0 = _dateOnly(day);
    final t0 = _dateOnly(t);
    final diff = t0.difference(d0).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_weekdays[d0.weekday - 1]} ${d0.day} ${_months[d0.month - 1]}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
