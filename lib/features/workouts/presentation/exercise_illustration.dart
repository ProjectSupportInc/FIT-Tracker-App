import 'package:flutter/material.dart';

/// Small vector illustrations stay sharp at any text/display size.
class ExerciseIllustration extends StatelessWidget {
  const ExerciseIllustration(
      {super.key,
      required this.kind,
      this.motion = 0,
      this.size = 130,
      this.color});
  final String kind;
  final double motion, size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
          child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
            painter: _ExercisePainter(kind.toLowerCase(), motion,
                color ?? Theme.of(context).colorScheme.primary)),
      ));
}

class _ExercisePainter extends CustomPainter {
  _ExercisePainter(this.kind, this.motion, this.color);
  final String kind;
  final double motion;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    void line(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pen);
    }

    void head(double x, double y) =>
        canvas.drawCircle(Offset(x, y), 7, Paint()..color = color);
    void weight(double x, double y) {
      line([Offset(x - 10, y), Offset(x + 10, y)]);
      line([Offset(x - 8, y - 7), Offset(x - 8, y + 7)]);
      line([Offset(x + 8, y - 7), Offset(x + 8, y + 7)]);
    }

    if (kind.contains('push')) {
      final shoulder = Offset(24, 56 + motion * 18);
      head(13, shoulder.dy - 7);
      line([shoulder, Offset(61, 73 + motion * 8), const Offset(91, 87)]);
      line([shoulder, Offset(29 + motion * 13, 72), const Offset(23, 87)]);
      line([const Offset(15, 92), const Offset(96, 92)]);
    } else if (kind.contains('squat')) {
      head(50 - motion * 6, 16 + motion * 15);
      final shoulder = Offset(50 - motion * 6, 31 + motion * 15);
      final hip = Offset(48 - motion * 12, 60 + motion * 6);
      line([shoulder, hip, Offset(57 + motion * 15, 75), const Offset(48, 92)]);
      line([
        shoulder,
        Offset(72, 35 + motion * 15),
        Offset(87, 35 + motion * 15)
      ]);
      line([const Offset(42, 93), const Offset(60, 93)]);
    } else if (kind.contains('bench')) {
      head(15, 49);
      line([
        const Offset(28, 55),
        const Offset(63, 55),
        const Offset(78, 70),
        const Offset(83, 90)
      ]);
      line([const Offset(8, 65), const Offset(68, 65)]);
      line([const Offset(18, 65), const Offset(18, 90)]);
      line([
        const Offset(38, 55),
        Offset(48, 40 + motion * 5),
        Offset(45, 17 + motion * 17)
      ]);
      weight(45, 13 + motion * 17);
    } else if (kind.contains('row')) {
      head(26, 22);
      line([
        const Offset(37, 33),
        const Offset(62, 57),
        const Offset(73, 73),
        const Offset(67, 93)
      ]);
      line([const Offset(62, 57), const Offset(40, 75), const Offset(32, 93)]);
      line([
        const Offset(37, 33),
        Offset(24 + motion * 17, 53),
        Offset(24 + motion * 15, 72 - motion * 21)
      ]);
      weight(24 + motion * 15, 76 - motion * 21);
    } else if (kind.contains('shoulder') || kind.contains('press')) {
      head(50, 23);
      line([const Offset(50, 38), const Offset(50, 66), const Offset(35, 92)]);
      line([const Offset(50, 66), const Offset(65, 92)]);
      for (final direction in [-1, 1]) {
        line([
          const Offset(50, 40),
          Offset(50 + direction * 22, 36),
          Offset(50 + direction * 25, 9 + motion * 17)
        ]);
        weight(50 + direction * 25, 7 + motion * 17);
      }
    } else if (kind.contains('curl')) {
      head(43, 14);
      line([const Offset(43, 29), const Offset(43, 64), const Offset(32, 92)]);
      line([const Offset(43, 64), const Offset(55, 92)]);
      line([
        const Offset(43, 34),
        const Offset(60, 55),
        Offset(77, 60 - motion * 30)
      ]);
      weight(79, 60 - motion * 30);
    } else {
      line([
        const Offset(20, 90),
        const Offset(20, 15),
        const Offset(80, 15),
        const Offset(80, 90)
      ]);
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(32, 49 + i * 12 - motion * 20, 36, 8),
                const Radius.circular(2)),
            pen);
      }
      line([const Offset(50, 15), Offset(50, 43 - motion * 20)]);
    }
  }

  @override
  bool shouldRepaint(_ExercisePainter old) =>
      old.kind != kind || old.motion != motion || old.color != color;
}
