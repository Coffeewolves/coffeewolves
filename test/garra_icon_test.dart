import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wolves_club/garra_icon.dart';

void main() {
  testWidgets('renders the supplied paw with visible claws and its tint',
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
    final imageFinder =
        find.descendant(of: icon, matching: find.byType(Image));
    expect(
      imageFinder,
      findsOneWidget,
    );
    expect(find.descendant(of: icon, matching: find.byType(CustomPaint)),
        findsNothing);
    expect(
      find.descendant(of: icon, matching: find.byType(Icon)),
      findsNothing,
    );

    final image = tester.widget<Image>(imageFinder);
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName,
        'assets/images/menu_icons/wolf_paw_claws.png');
    expect(image.color, garraColor);
    expect(image.colorBlendMode, BlendMode.srcIn);
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
