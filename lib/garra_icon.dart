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
      child: CustomPaint(
        painter: _GarraPainter(effectiveColor, shadows ?? const []),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: semanticLabel, child: icon);
  }
}

class _GarraPainter extends CustomPainter {
  const _GarraPainter(this.color, this.shadows);

  final Color color;
  final List<Shadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final claws = [
      Path()
        ..moveTo(4.2, 3.1)
        ..cubicTo(2.9, 9, 3.8, 15.7, 6.8, 21)
        ..cubicTo(7.1, 21.6, 8, 21.2, 7.8, 20.5)
        ..cubicTo(6.7, 15, 6.8, 9.3, 8.9, 3.7)
        ..cubicTo(9.5, 2.1, 4.9, 1.6, 4.2, 3.1)
        ..close(),
      Path()
        ..moveTo(10.1, 2.5)
        ..cubicTo(9.1, 8.9, 9.8, 15.6, 11.5, 21.5)
        ..cubicTo(11.7, 22.2, 12.8, 22.2, 12.9, 21.5)
        ..cubicTo(13, 15.5, 13.7, 8.9, 14.7, 2.5)
        ..cubicTo(14.9, 1.2, 10.3, 1.2, 10.1, 2.5)
        ..close(),
      Path()
        ..moveTo(16.1, 3.7)
        ..cubicTo(17.9, 9.2, 18, 14.9, 16.7, 20.5)
        ..cubicTo(16.5, 21.2, 17.4, 21.6, 17.7, 21)
        ..cubicTo(20.7, 15.7, 21.6, 9, 20.3, 3.1)
        ..cubicTo(19.6, 1.6, 15.5, 2.1, 16.1, 3.7)
        ..close(),
    ];
    for (final claw in claws) {
      for (final shadow in shadows) {
        canvas.save();
        canvas.translate(shadow.offset.dx, shadow.offset.dy);
        canvas.drawShadow(claw, shadow.color, shadow.blurRadius, false);
        canvas.restore();
      }
      canvas.drawPath(claw, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GarraPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shadows != shadows;
}
