import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'collectible_models.dart';

class CollectibleTransferService {
  CollectibleTransferService({
    required FirebaseFirestore firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _actorUid {
    final user = _auth.currentUser;
    if (user == null ||
        user.isAnonymous ||
        (!user.emailVerified && user.phoneNumber == null)) {
      throw StateError(
        'Inicia sesión con una cuenta Wolves verificada por correo o teléfono.',
      );
    }
    return user.uid;
  }

  Future<String> requestTransfer({
    required String collectibleCode,
    required String recipientUid,
  }) async {
    final actorUid = _actorUid;
    final code = _normalizeCode(collectibleCode);
    final recipient = recipientUid.trim();
    if (recipient.isEmpty || recipient == actorUid) {
      throw ArgumentError('El destinatario debe ser otra cuenta Wolves.');
    }

    final collectibleRef = _firestore.collection('collectiblePlushes').doc(code);
    final authenticityRef =
        _firestore.collection('plushAuthenticity').doc(code);
    final transferRef =
        _firestore.collection('plushOwnershipTransfers').doc();
    final historyRef =
        _firestore.collection('plushOwnershipTransferHistory').doc();

    await _firestore.runTransaction((transaction) async {
      final collectible = await transaction.get(collectibleRef);
      final authenticity = await transaction.get(authenticityRef);
      if (!collectible.exists || !authenticity.exists) {
        throw StateError('La pieza no se encontró en el registro oficial.');
      }
      final unit = collectible.data()!;
      if (unit['claimedBy'] != actorUid ||
          authenticity.data()?['status'] != 'adopted') {
        throw StateError('Solo el titular actual puede transferir esta pieza.');
      }
      if (unit.containsKey('pendingTransferId')) {
        throw StateError('La pieza ya tiene una transferencia pendiente.');
      }

      final now = FieldValue.serverTimestamp();
      transaction.update(collectibleRef, {
        'pendingTransferId': transferRef.id,
      });
      transaction.set(transferRef, {
        'collectibleCode': code,
        'fromUid': actorUid,
        'toUid': recipient,
        'status': 'pending',
        'requestedAt': now,
        'respondedAt': null,
        'lastHistoryId': historyRef.id,
      });
      transaction.set(historyRef, {
        'transferId': transferRef.id,
        'collectibleCode': code,
        'action': 'requested',
        'actorUid': actorUid,
        'fromUid': actorUid,
        'toUid': recipient,
        'createdAt': now,
      });
    });
    return transferRef.id;
  }

  Future<void> acceptTransfer(String transferId) async {
    await _respondToTransfer(transferId, accept: true);
  }

  Future<void> rejectTransfer(String transferId) async {
    await _respondToTransfer(transferId, accept: false);
  }

  Future<void> cancelTransfer(String transferId) async {
    final actorUid = _actorUid;
    final transferRef =
        _firestore.collection('plushOwnershipTransfers').doc(transferId);
    final historyRef =
        _firestore.collection('plushOwnershipTransferHistory').doc();

    await _firestore.runTransaction((transaction) async {
      final transferSnapshot = await transaction.get(transferRef);
      if (!transferSnapshot.exists) {
        throw StateError('La transferencia no existe.');
      }
      final transfer = transferSnapshot.data()!;
      if (transfer['fromUid'] != actorUid ||
          transfer['status'] != 'pending') {
        throw StateError(
          'Solo quien solicitó una transferencia pendiente puede cancelarla.',
        );
      }
      final code = _normalizeCode(transfer['collectibleCode'] as String);
      final collectibleRef =
          _firestore.collection('collectiblePlushes').doc(code);
      final collectibleSnapshot = await transaction.get(collectibleRef);
      if (!collectibleSnapshot.exists ||
          collectibleSnapshot.data()?['pendingTransferId'] != transferRef.id) {
        throw StateError('La pieza ya no tiene esta transferencia pendiente.');
      }

      final now = FieldValue.serverTimestamp();
      transaction.update(transferRef, {
        'status': 'cancelled',
        'respondedAt': now,
        'lastHistoryId': historyRef.id,
      });
      transaction.update(collectibleRef, {
        'pendingTransferId': FieldValue.delete(),
      });
      transaction.set(historyRef, {
        'transferId': transferRef.id,
        'collectibleCode': code,
        'action': 'cancelled',
        'actorUid': actorUid,
        'fromUid': actorUid,
        'toUid': transfer['toUid'],
        'createdAt': now,
      });
    });
  }

  Future<void> _respondToTransfer(
    String transferId, {
    required bool accept,
  }) async {
    final actorUid = _actorUid;
    final transferRef =
        _firestore.collection('plushOwnershipTransfers').doc(transferId);
    final historyRef =
        _firestore.collection('plushOwnershipTransferHistory').doc();

    await _firestore.runTransaction((transaction) async {
      final transferSnapshot = await transaction.get(transferRef);
      if (!transferSnapshot.exists) {
        throw StateError('La transferencia no existe.');
      }
      final transfer = transferSnapshot.data()!;
      if (transfer['toUid'] != actorUid ||
          transfer['status'] != 'pending') {
        throw StateError(
          'Solo el destinatario puede responder una transferencia pendiente.',
        );
      }

      final code = _normalizeCode(transfer['collectibleCode'] as String);
      final collectibleRef =
          _firestore.collection('collectiblePlushes').doc(code);
      final certificateRef =
          _firestore.collection('plushCertificates').doc(code);
      final collectibleSnapshot = await transaction.get(collectibleRef);
      if (!collectibleSnapshot.exists ||
          collectibleSnapshot.data()?['pendingTransferId'] != transferRef.id ||
          collectibleSnapshot.data()?['claimedBy'] != transfer['fromUid']) {
        throw StateError('La titularidad de la pieza cambió.');
      }

      final now = FieldValue.serverTimestamp();
      transaction.update(transferRef, {
        'status': accept ? 'accepted' : 'rejected',
        'respondedAt': now,
        'lastHistoryId': historyRef.id,
      });
      transaction.update(collectibleRef, {
        if (accept) 'claimedBy': actorUid,
        if (accept) 'claimedByName': null,
        'pendingTransferId': FieldValue.delete(),
      });
      if (accept) {
        transaction.update(certificateRef, {
          'ownerUid': actorUid,
          'ownerName': null,
        });
      }
      transaction.set(historyRef, {
        'transferId': transferRef.id,
        'collectibleCode': code,
        'action': accept ? 'accepted' : 'rejected',
        'actorUid': actorUid,
        'fromUid': transfer['fromUid'],
        'toUid': actorUid,
        'createdAt': now,
      });
    });
  }

  String _normalizeCode(String value) {
    final code = value.trim().toUpperCase();
    if (!isValidCollectibleModelUnit(code)) {
      throw ArgumentError.value(value, 'collectibleCode', 'Código inválido.');
    }
    return code;
  }
}
