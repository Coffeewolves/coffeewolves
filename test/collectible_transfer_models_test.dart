import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/collectible_transfer_models.dart';

void main() {
  group('CollectibleTransfer', () {
    test('round-trips transfer data and status', () {
      final requestedAt = DateTime.utc(2026, 10, 9, 12);
      final transfer = CollectibleTransfer(
        id: 'transfer-1',
        collectibleCode: 'CW-PLUSH-001-0001',
        fromUid: 'owner-1',
        toUid: 'owner-2',
        status: CollectibleTransferStatus.pending,
        requestedAt: requestedAt,
        lastHistoryId: 'history-1',
      );

      final decoded = CollectibleTransfer.fromMap(
        transfer.id,
        transfer.toMap(),
      );

      expect(decoded.collectibleCode, transfer.collectibleCode);
      expect(decoded.fromUid, transfer.fromUid);
      expect(decoded.toUid, transfer.toUid);
      expect(decoded.status, CollectibleTransferStatus.pending);
      expect(decoded.requestedAt, requestedAt);
      expect(decoded.respondedAt, isNull);
    });

    test('rejects unknown persisted status', () {
      expect(
        () => CollectibleTransferStatus.fromValue('completed'),
        throwsFormatException,
      );
    });

    test('accepts transfers for the newly registered model codes', () {
      final transfer = CollectibleTransfer(
        id: 'transfer-pomi',
        collectibleCode: 'CW-PLUSH-007-0001',
        fromUid: 'owner-1',
        toUid: 'owner-2',
        status: CollectibleTransferStatus.pending,
        requestedAt: DateTime.utc(2026, 10, 9, 12),
        lastHistoryId: 'history-pomi',
      );

      expect(
        CollectibleTransfer.fromMap(transfer.id, transfer.toMap())
            .collectibleCode,
        'CW-PLUSH-007-0001',
      );
    });

    test('rejects a transfer to the current owner', () {
      final transfer = CollectibleTransfer(
        id: 'transfer-1',
        collectibleCode: 'CW-PLUSH-001-0001',
        fromUid: 'same-user',
        toUid: 'same-user',
        status: CollectibleTransferStatus.pending,
        requestedAt: DateTime.utc(2026, 10, 9, 12),
        lastHistoryId: 'history-1',
      );

      expect(transfer.toMap, throwsFormatException);
    });
  });

  test('round-trips immutable transfer history', () {
    final entry = CollectibleTransferHistoryEntry(
      id: 'history-1',
      transferId: 'transfer-1',
      collectibleCode: 'CW-PLUSH-001-0001',
      action: CollectibleTransferAction.accepted,
      actorUid: 'owner-2',
      fromUid: 'owner-1',
      toUid: 'owner-2',
      createdAt: DateTime.utc(2026, 10, 9, 12, 5),
    );

    final decoded = CollectibleTransferHistoryEntry.fromMap(
      entry.id,
      entry.toMap(),
    );

    expect(decoded.action, CollectibleTransferAction.accepted);
    expect(decoded.actorUid, entry.actorUid);
    expect(decoded.createdAt, entry.createdAt);
  });
}
