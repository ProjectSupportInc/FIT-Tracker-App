// Formats dates for screen labels and compares calendar dates without comparing times.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/home/presentation/today_screen.dart
// - lib/features/progress/presentation/progress_screen.dart
// - lib/features/workouts/domain/workout_policy.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart
// - lib/features/workouts/presentation/workouts_screen.dart

/// Month names indexed by month minus one; used by date-formatting helpers.
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Weekday names indexed by weekday minus one; used by weekdayLabel().
const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Returns a full weekday name; used by shortWeekday() and longDate().
String weekdayLabel(DateTime day) => _days[day.weekday - 1];

/// Returns a three-letter weekday; TodayScreen._calendar() uses it to build day labels.
String shortWeekday(DateTime day) => weekdayLabel(day).substring(0, 3);

/// Returns a three-letter month name; used by shortDate().
String shortMonth(DateTime day) => _months[day.month - 1].substring(0, 3);

/// Formats a full weekday/month/day label for TodayScreen and WorkoutsScreen.
String longDate(DateTime day) =>
    '${weekdayLabel(day)}, ${_months[day.month - 1]} ${day.day}';

/// Formats a compact month/day label for workout lists, details, and progress history.
String shortDate(DateTime day) => '${shortMonth(day)} ${day.day}';

/// Formats a 12-hour time with AM/PM for WorkoutCard and WorkoutDetailScreen.
String friendlyTime(DateTime date) {
  /// 12-hour clock value, treating midnight and noon as 12.
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;

  /// Two-digit minute string used in friendlyTime().
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

/// Compares only year/month/day; used by TodayScreen, WorkoutsScreen, and WorkoutPolicy.
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
