import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/cold_brew_qr_payload.dart';
import 'package:wolves_club/membership_card_widget.dart';

void main() {
  test('membership QR includes its member ID and name in structured data', () {
    final payload = membershipCardQrPayload(
      memberId: 'WLV-M-000001',
      memberName: 'Ana Wolves',
    );

    final decodedPayload = jsonDecode(payload) as Map<String, dynamic>;
    expect(decodedPayload['type'], 'wolves_member_card');
    expect(decodedPayload['memberId'], 'WLV-M-000001');
    expect(decodedPayload['memberName'], 'Ana Wolves');
    expect(memberCardValueFromQr(payload), 'WLV-M-000001');
  });

  testWidgets('shows the member ID and name on the card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WolvesMembershipCard(
            memberName: 'Ana Wolves',
            memberId: 'WLV-M-000001',
          ),
        ),
      ),
    );

    expect(find.text('ANA WOLVES'), findsOneWidget);
    expect(find.text('WLV-M-000001'), findsOneWidget);
    await tester.tap(find.text('REVERSO · QR'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('membership-qr-WLV-M-000001')),
      findsOneWidget,
    );
    expect(find.text('IDENTIFICACIÓN DE MIEMBRO'), findsOneWidget);
  });
}
