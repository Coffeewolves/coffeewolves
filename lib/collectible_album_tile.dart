import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'collectible_models.dart';

class CollectibleAlbumTile extends StatefulWidget {
  const CollectibleAlbumTile({
    required this.entry,
    required this.silhouette,
    required this.cardColor,
    required this.gold,
    required this.cream,
    required this.muted,
    required this.lockedColor,
    this.imageAsset,
    super.key,
  });

  final CollectibleAlbumEntry entry;
  final IconData silhouette;
  final Color cardColor;
  final Color gold;
  final Color cream;
  final Color muted;
  final Color lockedColor;
  final String? imageAsset;

  @override
  State<CollectibleAlbumTile> createState() => _CollectibleAlbumTileState();
}

class _CollectibleAlbumTileState extends State<CollectibleAlbumTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void didUpdateWidget(covariant CollectibleAlbumTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.entry.unlocked && widget.entry.unlocked) {
      _rotationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.entry.unlocked;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? widget.gold.withValues(alpha: 0.7) : widget.muted,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Semantics(
              label:
                  '${widget.entry.name}, ${unlocked ? 'desbloqueada' : 'por descubrir'}',
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AnimatedBuilder(
                      animation: _rotationController,
                      builder: (context, child) => Transform(
                        key: ValueKey(
                          'collectible-unlock-spin-${widget.entry.id}',
                        ),
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(
                          math.pi * 2 * _rotationController.value,
                        ),
                        child: child,
                      ),
                      child: ClipOval(
                        child: Container(
                          width: 70,
                          height: 70,
                          alignment: Alignment.center,
                          color: unlocked
                              ? widget.gold.withValues(alpha: 0.12)
                              : const Color(0xFF171A1B),
                          child: widget.imageAsset == null
                              ? Icon(
                                  widget.silhouette,
                                  size: 46,
                                  color: unlocked
                                      ? widget.gold
                                      : widget.lockedColor,
                                )
                              : Image.asset(
                                  widget.imageAsset!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                    widget.silhouette,
                                    size: 46,
                                    color: unlocked
                                        ? widget.gold
                                        : widget.lockedColor,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!unlocked)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF171A1B).withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.muted.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          color: widget.cream,
                          size: 19,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.cream,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            unlocked ? 'DESBLOQUEADA' : 'POR DESCUBRIR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: unlocked ? widget.gold : widget.muted,
              fontSize: 8,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
