import 'package:flutter/material.dart';

import '../core/theme.dart';

class BatteryChart extends CustomPainter {
  BatteryChart(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lime
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final grid = Paint()
      ..color = const Color(0xFF29372D)
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    final start = DateTime.parse(rows.first['observedAt'] as String)
        .millisecondsSinceEpoch;
    final end = DateTime.parse(rows.last['observedAt'] as String)
        .millisecondsSinceEpoch;
    final path = Path();
    for (var i = 0; i < rows.length; i++) {
      final time = DateTime.parse(rows[i]['observedAt'] as String)
          .millisecondsSinceEpoch;
      final percentage = ((rows[i]['battery'] as Map)['percentage'] as num)
          .toDouble();
      final x = end == start
          ? size.width * i / (rows.length - 1)
          : size.width * (time - start) / (end - start);
      final y = size.height * (1 - percentage.clamp(0, 100) / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BatteryChart oldDelegate) =>
      oldDelegate.rows != rows;
}
