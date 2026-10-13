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

  group('Collectible album catalog', () {
    test('contains 27 cups and six plushes across the three breeds', () {
      final album = buildCollectibleAlbum();
      final cups = album
          .where((entry) => entry.type == CollectibleAlbumType.cup)
          .toList();
      final plushes = album
          .where((entry) => entry.type == CollectibleAlbumType.plush)
          .toList();

      expect(album, hasLength(33));
      expect(cups, hasLength(27));
      expect(plushes, hasLength(6));
      expect(
        collectibleAlbumBreeds.map((breed) => breed.name),
        ['Pomeranian', 'Samoyed', 'Husky'],
      );
      for (final breed in collectibleAlbumBreeds) {
        expect(
          cups.where((entry) => entry.breedId == breed.id),
          hasLength(9),
        );
        expect(
          plushes.where((entry) => entry.breedId == breed.id),
          hasLength(2),
        );
      }
      expect(cups.map((entry) => entry.methodId).toSet(), hasLength(9));
      expect(album.every((entry) => !entry.unlocked), isTrue);
    });

    test('unlocks only owned plushes and cups with a recorded method', () {
      final album = buildCollectibleAlbum(
        ownedModelCodes: {'CW-PLUSH-001', 'CW-CUP-007'},
        ownedCupMethodIds: {'chemex'},
      );

      expect(
        album.singleWhere((entry) => entry.id == 'plush-pomi-1').unlocked,
        isTrue,
      );
      expect(
        album.singleWhere((entry) => entry.id == 'plush-pomi-2').unlocked,
        isFalse,
      );
      expect(
        album.singleWhere((entry) => entry.id == 'cup-pomi-chemex').unlocked,
        isTrue,
      );
      expect(
        album.singleWhere((entry) => entry.id == 'cup-pomi-cold-brew').unlocked,
        isFalse,
      );
      expect(
        album
            .where((entry) => entry.breedId != 'pomi')
            .every((entry) => !entry.unlocked),
        isTrue,
      );
    });
  });
}
