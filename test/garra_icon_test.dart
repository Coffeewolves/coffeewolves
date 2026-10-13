import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/garra_icon.dart';

void main() {
  testWidgets('renders the garra marker with the custom icon painter',
      (tester) async {
    const iconKey = ValueKey('garra-test-icon');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WolvesIcon(
            key: iconKey,
            icon: BrandIcons.garra,
            size: 32,
            color: Color(0xFFC6A06A),
          ),
        ),
      ),
    );

    final icon = find.byKey(iconKey);
    expect(
      find.descendant(of: icon, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: icon, matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('keeps standard Material icons unchanged', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WolvesIcon(icon: Icons.coffee, size: 24),
        ),
      ),
    );

    expect(find.byIcon(Icons.coffee), findsOneWidget);
  });
}
