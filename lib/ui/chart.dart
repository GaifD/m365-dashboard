import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Простой линейный график: значения по оси X равномерно (секунды поездки).
/// null в данных — разрыв линии. Отрицательные значения рисуются другим цветом.
class LineChart extends StatelessWidget {
  final List<double?> values;
  final Color color;
  final Color negativeColor;
  final String unit;
  final int totalSec;
  final double height;

  const LineChart({
    super.key,
    required this.values,
    required this.unit,
    required this.totalSec,
    this.color = C.accent,
    this.negativeColor = C.amber,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ChartPainter(values, color, negativeColor, unit, totalSec),
        ),
      );
}

class _ChartPainter extends CustomPainter {
  final List<double?> v;
  final Color color;
  final Color neg;
  final String unit;
  final int totalSec;

  _ChartPainter(this.v, this.color, this.neg, this.unit, this.totalSec);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 0.0;
    const bottomPad = 18.0;
    const topPad = 16.0;
    final w = size.width;
    final h = size.height - bottomPad - topPad;
    final vals = v.whereType<double>().toList();
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset at, {TextAlign align = TextAlign.left}) {
      tp.text = TextSpan(text: t, style: const TextStyle(fontSize: 10, color: C.faint));
      tp.layout();
      final dx = align == TextAlign.right ? at.dx - tp.width : at.dx;
      tp.paint(canvas, Offset(dx, at.dy));
    }

    if (vals.length < 2) {
      label('Мало данных', Offset(w / 2 - 30, size.height / 2 - 6));
      return;
    }
    var lo = vals.reduce(math.min);
    var hi = vals.reduce(math.max);
    if (lo > 0) lo = 0;
    if (hi - lo < 1e-6) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    hi += pad;
    if (lo < 0) lo -= pad;
    double y(double val) => topPad + h - (val - lo) / (hi - lo) * h;

    final grid = Paint()
      ..color = const Color(0xFF1E2830)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final yy = topPad + h * i / 3;
      canvas.drawLine(Offset(left, yy), Offset(w, yy), grid);
    }
    if (lo < 0) {
      canvas.drawLine(Offset(left, y(0)), Offset(w, y(0)), Paint()..color = C.muted.withValues(alpha: 0.5));
    }

    final n = v.length;
    double x(int i) => left + (n <= 1 ? 0 : i / (n - 1) * (w - left));
    final pos = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final negP = Paint()
      ..color = neg
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    Path? path;
    for (var i = 0; i < n; i++) {
      final val = v[i];
      if (val == null) {
        if (path != null) canvas.drawPath(path, pos);
        path = null;
        continue;
      }
      final p = Offset(x(i), y(val < 0 ? 0 : val));
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      if (val < 0) {
        canvas.drawLine(Offset(x(i), y(0)), Offset(x(i), y(val)), negP);
      }
    }
    if (path != null) canvas.drawPath(path, pos);

    String f(double d) => d.abs() >= 100 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    label('${f(hi)} $unit', const Offset(2, 0));
    if (lo < 0) label('${f(lo)} $unit', Offset(2, topPad + h - 12));
    label('0:00', Offset(0, size.height - 13));
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    label('$m:${s.toString().padLeft(2, '0')}', Offset(w, size.height - 13), align: TextAlign.right);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.v != v || old.color != color;
}
