const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _days = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

String weekdayLabel(DateTime day) => _days[day.weekday - 1];
String shortWeekday(DateTime day) => weekdayLabel(day).substring(0, 3);
String shortMonth(DateTime day) => _months[day.month - 1].substring(0, 3);
String longDate(DateTime day) => '${weekdayLabel(day)}, ${_months[day.month - 1]} ${day.day}';
String shortDate(DateTime day) => '${shortMonth(day)} ${day.day}';
String friendlyTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
