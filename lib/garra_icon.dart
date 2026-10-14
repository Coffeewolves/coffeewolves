import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

abstract final class BrandIcons {
  static const IconData garra = Icons.pets;
}

const _garraAssetPath = 'assets/images/menu_icons/wolf_paw_claws.png';

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
                  child: _garraImage(shadow.color),
                ),
              ),
            ),
          Positioned.fill(child: _garraImage(effectiveColor)),
        ],
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: semanticLabel, child: icon);
  }

  Widget _garraImage(Color imageColor) => Image.asset(
        _garraAssetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        color: imageColor,
        colorBlendMode: BlendMode.srcIn,
      );
}
