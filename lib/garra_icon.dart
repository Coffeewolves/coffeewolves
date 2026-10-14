import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

abstract final class BrandIcons {
  static const IconData garra = Icons.pets;
}

class WolvesIcon extends StatelessWidget {
  const WolvesIcon({
    super.key,
    required this.icon,
    this.size,
    this.color,
    this.semanticLabel,
    this.shadows,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    if (icon != BrandIcons.garra) {
      return Icon(
        icon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        shadows: shadows,
      );
    }

    final theme = IconTheme.of(context);
    final effectiveSize = size ?? theme.size ?? 24;
    final effectiveColor = color ??
        theme.color ??
        Theme.of(context).iconTheme.color ??
        Theme.of(context).colorScheme.onSurface;
    final garra = GarraIcon(
      size: effectiveSize,
      color: effectiveColor,
      semanticLabel: semanticLabel,
      shadows: shadows,
    );
    return semanticLabel == null ? ExcludeSemantics(child: garra) : garra;
  }
}

class GarraIcon extends StatelessWidget {
  const GarraIcon({
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
    this.shadows,
  });

  final double size;
  final Color? color;
  final String? semanticLabel;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        IconTheme.of(context).color ??
        Theme.of(context).iconTheme.color ??
        Theme.of(context).colorScheme.onSurface;
    final icon = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final shadow in shadows ?? const [])
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(
                  shadow.offset.dx * size / 24,
                  shadow.offset.dy * size / 24,
                ),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: shadow.blurRadius * size / 48,
                    sigmaY: shadow.blurRadius * size / 48,
                  ),
                  child: CustomPaint(
                    painter: _GarraPainter(shadow.color),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GarraPainter(effectiveColor),
            ),
          ),
        ],
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: semanticLabel, child: icon);
  }
}

class _GarraPainter extends CustomPainter {
  const _GarraPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale, scale);

    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const toes = <({Offset center, double rotation})>[
      (center: Offset(20, 35), rotation: -0.34),
      (center: Offset(40, 25), rotation: -0.12),
      (center: Offset(60, 25), rotation: 0.12),
      (center: Offset(80, 35), rotation: 0.34),
    ];
    for (final toe in toes) {
      canvas.save();
      canvas.translate(toe.center.dx, toe.center.dy);
      canvas.rotate(toe.rotation);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 17, height: 23),
        outline,
      );
      final claw = Path()
        ..moveTo(-4, -10)
        ..quadraticBezierTo(-3, -15, 0, -21)
        ..quadraticBezierTo(3, -15, 4, -10);
      canvas.drawPath(claw, outline);
      canvas.restore();
    }

    final pad = Path()
      ..moveTo(50, 84)
      ..cubicTo(43, 80, 29, 70, 29, 60)
      ..cubicTo(29, 49, 42, 46, 50, 55)
      ..cubicTo(58, 46, 71, 49, 71, 60)
      ..cubicTo(71, 70, 57, 80, 50, 84);
    canvas.drawPath(pad, outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GarraPainter oldDelegate) =>
      oldDelegate.color != color;
}
