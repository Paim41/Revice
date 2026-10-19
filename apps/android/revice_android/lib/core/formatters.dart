/// Formats a percentage for display without modifying the measured value.
String formatPercentage(num? value) =>
    value == null ? 'Unavailable' : '${value.toStringAsFixed(2)}%';

String compactPercentage(num? value, {bool battery = false}) {
  if (value == null || !value.isFinite || value < 0 || value > 100) {
    return 'N/A';
  }
  final text = value.toStringAsFixed(battery ? 0 : 1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}%';
}

String platformLabel(Object? value) => switch (value) {
  'windows' => 'Windows',
  'android' => 'Android',
  _ => 'Device',
};

String friendlyTime(DateTime? value) {
  if (value == null) return 'Unknown Time';
  final t = value.toLocal();
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
  return '${t.day} ${months[t.month - 1]} ${t.year}, ${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String? deviceNameError(String input) {
  if (RegExp(
    r'[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]',
  ).hasMatch(input)) {
    return 'Control characters are not allowed.';
  }
  final name = input.trim();
  if (name.isEmpty) return 'Enter a device name.';
  if (name.runes.length > 40) return 'Use no more than 40 characters.';
  return null;
}
