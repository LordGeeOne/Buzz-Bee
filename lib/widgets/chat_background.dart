import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Subtle honeycomb-pattern background for the chat list.
///
/// The hexagons are stroked with [color] (typically the active theme's
/// primary) at very low opacity so the pattern reads as texture, not noise.
/// Pure painter — no images, no rebuilds beyond color/size changes — so it's
/// cheap to keep behind the message list.
class ChatBackground extends StatelessWidget {
  final Color color;
  final Widget child;

  /// Hex cell radius in logical pixels. 28 gives a comfortable, calm density.
  final double cellRadius;

  /// 0.0 – 1.0 alpha applied to [color] for the stroke.
  final double opacity;

  const ChatBackground({
    super.key,
    required this.color,
    required this.child,
    this.cellRadius = 32,
    this.opacity = 0.025,
    this.background,
  });

  /// Optional solid fill drawn behind the pattern. Defaults to transparent
  /// so the parent background shows through.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (background != null)
          Positioned.fill(child: ColoredBox(color: background!)),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _HoneycombPainter(
                color: color.withValues(alpha: opacity),
                radius: cellRadius,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _HoneycombPainter extends CustomPainter {
  final Color color;
  final double radius;

  _HoneycombPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;

    final hexHeight = radius * math.sqrt(3);
    final horizontalSpacing = radius * 1.5;
    // Stagger every other column down by half a row.
    var col = 0;
    for (double x = -radius; x < size.width + radius; x += horizontalSpacing) {
      final yOffset = (col.isOdd) ? hexHeight / 2 : 0.0;
      for (
        double y = -hexHeight + yOffset;
        y < size.height + hexHeight;
        y += hexHeight
      ) {
        _drawHex(canvas, paint, Offset(x, y), radius);
      }
      col++;
    }
  }

  void _drawHex(Canvas canvas, Paint paint, Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i; // flat-top hexagon
      final dx = center.dx + r * math.cos(angle);
      final dy = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HoneycombPainter old) {
    return old.color != color || old.radius != radius;
  }
}
