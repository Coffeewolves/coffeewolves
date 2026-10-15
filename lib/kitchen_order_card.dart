import 'dart:async';

import 'package:flutter/material.dart';

import 'kitchen_order.dart';

class KitchenOrderCard extends StatefulWidget {
  const KitchenOrderCard({
    super.key,
    required this.order,
    required this.onStart,
    required this.onComplete,
  });

  final KitchenOrder order;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  State<KitchenOrderCard> createState() => _KitchenOrderCardState();
}

class _KitchenOrderCardState extends State<KitchenOrderCard> {
  static const _cream = Color(0xFFF2E8D8);
  static const _warning = Color(0xFFFF8A80);
  static const _gold = Color(0xFFC6A06A);
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final elapsed = _now.difference(widget.order.createdAt);
    final seconds = elapsed.inSeconds.clamp(0, 999999);
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String get _serviceLabel => switch (widget.order.serviceType) {
        KitchenServiceType.dineIn => 'LOCAL',
        KitchenServiceType.takeaway => 'LLEVAR',
        KitchenServiceType.delivery => 'DELIVERY',
      };

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final header = order.tableNumber != null
        ? 'MESA ${order.tableNumber}'
        : order.customerName?.trim().isNotEmpty == true
            ? order.customerName!.trim()
            : 'PEDIDO ${(order.id.length > 6 ? order.id.substring(0, 6) : order.id).toUpperCase()}';
    final isPreparing = order.status == KitchenOrderStatus.preparing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF211D19),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPreparing ? _gold : _warning.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _elapsed,
                style: TextStyle(
                  color: isPreparing ? _gold : _warning,
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Tag(label: _serviceLabel),
              const SizedBox(width: 8),
              _Tag(label: isPreparing ? 'EN PREPARACIÓN' : 'PENDIENTE'),
            ],
          ),
          const Divider(height: 24, color: Color(0xFF51443A)),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${item.quantity} × ${item.name}'
                      '${item.size == null || item.size!.isEmpty ? '' : ' · ${item.size}'}',
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final note in item.modifications)
                      Container(
                        margin: const EdgeInsets.only(top: 5, left: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF8A80).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          note,
                          style: const TextStyle(
                            color: _warning,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: isPreparing ? widget.onComplete : widget.onStart,
            icon: Icon(
              isPreparing ? Icons.check_circle_outline : Icons.play_arrow,
            ),
            label: Text(isPreparing ? 'TERMINAR' : 'INICIAR'),
            style: FilledButton.styleFrom(
              backgroundColor: isPreparing ? const Color(0xFF718B68) : _gold,
              foregroundColor: const Color(0xFF171411),
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFC6A06A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFC6A06A),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
