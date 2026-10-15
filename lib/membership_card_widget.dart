import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'cold_brew_qr_payload.dart';

class WolvesMembershipCard extends StatefulWidget {
  const WolvesMembershipCard({
    required this.memberName,
    required this.memberId,
    super.key,
  });

  final String memberName;
  final String memberId;

  @override
  State<WolvesMembershipCard> createState() => _WolvesMembershipCardState();
}

class _WolvesMembershipCardState extends State<WolvesMembershipCard> {
  static const _burgundy = Color(0xFF4B1724);
  static const _cream = Color(0xFFF0E7D7);
  static const _silver = Color(0xFFC7C9CB);
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: AspectRatio(
            key: ValueKey(_showBack),
            aspectRatio: 8.55 / 5.4,
            child: _showBack ? _back : _front,
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('FRENTE')),
            ButtonSegment(value: true, label: Text('REVERSO · QR')),
          ],
          selected: {_showBack},
          onSelectionChanged: (selection) {
            setState(() => _showBack = selection.single);
          },
        ),
      ],
    );
  }

  Widget get _front => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF302A27), Color(0xFF111111), _burgundy],
            stops: [0, 0.65, 1],
          ),
          border: Border.all(color: _silver.withValues(alpha: 0.75)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/images/coffee_wolves_logo.webp',
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.pets,
                    color: _silver,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'COFFEE WOLVES',
                    style: TextStyle(
                      color: _cream,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                Icon(
                  Icons.workspace_premium_outlined,
                  color: _silver.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
            const Spacer(),
            Text(
              widget.memberName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _cream,
                fontSize: 16,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              widget.memberId,
              style: const TextStyle(
                color: _silver,
                fontSize: 13,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'WOLVES CLUB · MEMBRESÍA',
              style: TextStyle(
                color: _cream.withValues(alpha: 0.66),
                fontSize: 8,
                letterSpacing: 1.7,
              ),
            ),
          ],
        ),
      );

  Widget get _back => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF202020), Color(0xFF111111), _burgundy],
          ),
          border: Border.all(color: _silver.withValues(alpha: 0.75)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'IDENTIFICACIÓN DE MIEMBRO',
                    style: TextStyle(
                      color: _silver,
                      fontSize: 8,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.memberId,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'El QR contiene solo el ID público. Para canjes, la tarjeta debe vincularse a una cuenta Wolves Club.',
                    style: TextStyle(
                      color: _cream,
                      fontSize: 9,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: QrImageView(
                key: ValueKey('membership-qr-${widget.memberId}'),
                data: membershipCardQrPayload(
                  memberId: widget.memberId,
                  memberName: widget.memberName,
                ),
                size: 92,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
}
