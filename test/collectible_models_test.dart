import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/collectible_models.dart';

void main() {
  group('Wolves Original Collection model codes', () {
    test('groups plush and cup models with their display names and codes', () {
      expect(collectibleModelNames['CW-PLUSH-001'], 'El Alfa');
      expect(collectibleModelNames['CW-PLUSH-006'], 'El Protector');
      expect(
        collectibleModelsByCategory['PLUSH']!.keys,
        contains('CW-PLUSH-001'),
      );
      expect(
        collectibleModelsByCategory['CUPS'],
        {
          'CW-CUP-007': 'POMERANIAN',
          'CW-CUP-008': 'SAMOYED',
          'CW-CUP-009': 'HUSKY',
        },
      );

      // Old PLUSH identifiers remain valid for records already in Firestore.
      expect(collectibleModelNames['CW-PLUSH-007'], 'POMI');
      expect(collectibleModelNames['CW-PLUSH-008'], 'SAMO');
      expect(collectibleModelNames['CW-PLUSH-009'], 'HUSKY');
    });

    test('accepts registered units for legacy plush and current cup models',
        () {
      expect(isValidCollectibleModelUnit('CW-PLUSH-001-0001'), isTrue);
      expect(isValidCollectibleModelUnit('CW-PLUSH-007-0001'), isTrue);
      expect(isValidCollectibleModelUnit('CW-PLUSH-009-9999'), isTrue);
      expect(isValidCollectibleModelUnit('CW-CUP-007-0001'), isTrue);
      expect(isValidCollectibleModelUnit('CW-CUP-008-0001'), isTrue);
      expect(isValidCollectibleModelUnit('CW-CUP-009-0001'), isTrue);
    });

    test('rejects unknown models, malformed codes, and zero serials', () {
      expect(isValidCollectibleModel('CW-PLUSH-010'), isFalse);
      expect(isValidCollectibleModelUnit('CW-PLUSH-010-0001'), isFalse);
      expect(isValidCollectibleModelUnit('CW-PLUSH-007-0000'), isFalse);
      expect(isValidCollectibleModelUnit('CW-PLUSH-007'), isFalse);
      expect(isValidCollectibleModelUnit('CW-CUP-006-0001'), isFalse);
      expect(isValidCollectibleModelUnit('CW-CUP-010-0001'), isFalse);
    });
  });
}
