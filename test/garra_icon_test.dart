import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wolves_club/garra_icon.dart';

void main() {
  testWidgets('renders the complete garra silhouette with its tint',
      (tester) async {
    const iconKey = ValueKey('garra-test-icon');
    const garraColor = Color(0xFFC6A06A);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WolvesIcon(
            key: iconKey,
            icon: BrandIcons.garra,
            size: 32,
            color: garraColor,
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
      find.descendant(of: icon, matching: find.byType(Image)),
      findsNothing,
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
