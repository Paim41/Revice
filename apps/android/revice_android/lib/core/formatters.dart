/// Formats a percentage for display without modifying the measured value.
String formatPercentage(num? value) =>
    value == null ? 'Unavailable' : '${value.toStringAsFixed(2)}%';
