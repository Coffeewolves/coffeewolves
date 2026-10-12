import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/main.dart';

void main() {
  group('Coleccionable', () {
    test('construye, serializa y copia sus metadatos', () {
      final adoptedAt = DateTime(2026, 10, 8);
      final collectible = Coleccionable(
        code: 'CW-PLUSH-001-0001',
        modelCode: 'CW-PLUSH-001',
        character: 'El Alfa',
        serial: '0001',
        edition: 'Original Collection',
        adoptedAt: adoptedAt,
        nickname: 'Luna',
        notes: 'Primera pieza de la colección',
        isFavorite: true,
      );

      final copy = collectible.copyWith(nickname: 'Alfa Jr.');

      expect(collectible.toMap()['character'], 'El Alfa');
      expect(collectible.toMap()['nickname'], 'Luna');
      expect(copy.nickname, 'Alfa Jr.');
      expect(copy.code, collectible.code);
      expect(copy.isFavorite, isTrue);
      expect(copy.adoptedAt, adoptedAt);
    });

    test('lee números de serie enteros con cuatro dígitos', () {
      final collectible = Coleccionable.fromMap(
        'CW-PLUSH-002-0007',
        const {
          'modelCode': 'CW-PLUSH-002',
          'character': 'El Explorador',
          'serial': 7,
          'edition': 'Original Collection',
        },
      );

      expect(collectible.serial, '0007');
    });
  });

  group('Bitacora', () {
    const collectible = Coleccionable(
      code: 'CW-PLUSH-001-0001',
      modelCode: 'CW-PLUSH-001',
      character: 'El Alfa',
      serial: '0001',
      edition: 'Original Collection',
    );

    test('agrega una pieza sin mutar la bitácora anterior', () {
      final emptyLog = Bitacora(ownerUid: 'member-1');
      final updatedLog = emptyLog.agregarColeccionable(collectible);

      expect(emptyLog.coleccionables, isEmpty);
      expect(updatedLog.coleccionables, [collectible]);
      expect(updatedLog.ownerUid, 'member-1');
    });

    test('rechaza duplicados y actualiza solo una pieza existente', () {
      final log = Bitacora(
        ownerUid: 'member-1',
        coleccionables: [collectible],
      );
      final updated = log.actualizarColeccionable(
        collectible.copyWith(isFavorite: true),
      );

      expect(updated.coleccionables.single.isFavorite, isTrue);
      expect(log.coleccionables.single.isFavorite, isFalse);
      expect(
        () => log.agregarColeccionable(collectible),
        throwsStateError,
      );
      expect(
        () => log.actualizarColeccionable(
          const Coleccionable(
            code: 'CW-PLUSH-001-0002',
            modelCode: 'CW-PLUSH-001',
            character: 'El Alfa',
            serial: '0002',
            edition: 'Original Collection',
          ),
        ),
        throwsStateError,
      );
    });
  });
}
