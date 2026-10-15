import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemberCardService {
  MemberCardService(
    this._firestore, {
    FirebaseAuth? auth,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<String?> getPaidMemberCardNumber(String userUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw StateError(
        'Inicia sesión con tu cuenta Wolves Club para consultar tu Member Card.',
      );
    }
    if (userUid.isEmpty ||
        userUid.contains('/') ||
        currentUser.uid != userUid) {
      throw ArgumentError.value(userUid, 'userUid', 'Debe ser un UID válido.');
    }

    final card =
        await _firestore.collection('wolves_member_card').doc(userUid).get();
    if (!card.exists) return null;

    final data = card.data();
    final cardNumber = data?['memberCardNumber'];
    if (data?['userUid'] != userUid ||
        data?['status'] != 'active' ||
        cardNumber is! String ||
        !RegExp(r'^WLV-M-\d{6}$').hasMatch(cardNumber)) {
      throw const FormatException(
        'El registro de Member Card comprada no es válido o no está activo.',
      );
    }
    final lookup =
        await _firestore.collection('memberCardLookups').doc(cardNumber).get();
    if (!lookup.exists ||
        lookup.data()?['userUid'] != userUid ||
        lookup.data()?['cardNumber'] != cardNumber ||
        lookup.data()?['sequence'] != data?['sequence']) {
      throw const FormatException(
        'El identificador de Member Card no coincide con su cuenta.',
      );
    }
    return cardNumber;
  }

  Future<String> issuePaidMemberCard({
    required String userUid,
    required String memberName,
    required String issuedByUid,
    String? purchaseReference,
    String? requestId,
  }) async {
    if (userUid.isEmpty ||
        userUid.contains('/') ||
        memberName.trim().length < 2 ||
        issuedByUid.isEmpty ||
        _auth.currentUser?.uid != issuedByUid ||
        _auth.currentUser?.isAnonymous != false ||
        _auth.currentUser?.emailVerified != true) {
      throw ArgumentError('El cliente o la cuenta emisora no son válidos.');
    }

    final userRef = _firestore.collection('users').doc(userUid);
    final cardRef = _firestore.collection('wolves_member_card').doc(userUid);
    final counterRef =
        _firestore.collection('wolvesMemberCardCounters').doc('current');
    final legacyCounterRef =
        _firestore.collection('customerMemberCardCounters').doc('current');
    final requestRef = requestId == null
        ? null
        : _firestore.collection('memberCardRequests').doc(requestId);

    return _firestore.runTransaction((transaction) async {
      if (_auth.currentUser?.uid != issuedByUid) {
        throw StateError(
            'La sesión de Gerencia cambió. Inicia sesión otra vez.');
      }
      final userSnapshot = await transaction.get(userRef);
      final cardSnapshot = await transaction.get(cardRef);
      final counterSnapshot = await transaction.get(counterRef);
      final legacyCounterSnapshot = await transaction.get(legacyCounterRef);
      final requestSnapshot = requestRef == null
          ? null
          : await transaction.get(requestRef);
      if (!userSnapshot.exists || userSnapshot.data()?['role'] != 'user') {
        throw StateError('No encontramos una cuenta de cliente válida.');
      }
      if (cardSnapshot.exists) {
        throw StateError('Esta cuenta ya tiene una Member Card emitida.');
      }
      if (requestRef != null &&
          (!requestSnapshot!.exists ||
              requestSnapshot.data()?['status'] != 'payment_confirmed')) {
        throw StateError(
          'Gerencia debe confirmar primero el pago de la solicitud.',
        );
      }
      final lastSequence = counterSnapshot.data()?['lastSequence'];
      final lastCardNumber = counterSnapshot.data()?['lastCardNumber'];
      if (counterSnapshot.exists &&
          (lastSequence is! int ||
              lastSequence < 0 ||
              lastCardNumber is! String ||
              !RegExp(r'^WLV-M-\d{6}$').hasMatch(lastCardNumber) ||
              int.tryParse(lastCardNumber.substring(6)) != lastSequence)) {
        throw const FormatException(
          'El contador de Member Card no es válido.',
        );
      }
      final legacySequence = legacyCounterSnapshot.data()?['lastSequence'];
      final legacyCardNumber = legacyCounterSnapshot.data()?['lastCardNumber'];
      final legacyCardMatch = legacyCardNumber is String
          ? RegExp(r'^(?:CW-M|WLV-M)-(\d{6})$').firstMatch(legacyCardNumber)
          : null;
      if (legacyCounterSnapshot.exists &&
          (legacySequence is! int ||
              legacySequence < 0 ||
              legacyCardMatch == null ||
              int.tryParse(legacyCardMatch.group(1)!) != legacySequence)) {
        throw const FormatException(
          'El contador histórico de Member Cards no es válido.',
        );
      }
      final sequence = counterSnapshot.exists
          ? (lastSequence as int) + 1
          : legacyCounterSnapshot.exists
              ? (legacySequence as int) + 1
              : 1;
      if (sequence > 999999) {
        throw StateError('Se agotó la numeración de Member Card.');
      }

      final cardNumber = 'WLV-M-${sequence.toString().padLeft(6, '0')}';
      final lookupRef =
          _firestore.collection('memberCardLookups').doc(cardNumber);
      final lookupSnapshot = await transaction.get(lookupRef);
      final legacyLookupSnapshot = await transaction.get(
        _firestore.collection('customerMemberCardLookups').doc(cardNumber),
      );
      if (lookupSnapshot.exists || legacyLookupSnapshot.exists) {
        throw StateError('El número $cardNumber ya está asignado.');
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(cardRef, {
        'userUid': userUid,
        'memberCardNumber': cardNumber,
        'sequence': sequence,
        'fullName': memberName.trim(),
        'status': 'active',
        'issuedBy': issuedByUid,
        'createdAt': now,
        'purchaseReference': purchaseReference?.trim() ?? '',
      });
      transaction.set(lookupRef, {
        'userUid': userUid,
        'cardNumber': cardNumber,
        'sequence': sequence,
        'createdAt': now,
      });
      if (requestRef != null) {
        transaction.update(requestRef, {
          'userUid': userUid,
          'fullName': memberName.trim(),
          'memberCardNumber': cardNumber,
          'status': 'issued_pending_print',
          'issuedBy': issuedByUid,
          'issuedAt': now,
        });
      }
      if (counterSnapshot.exists) {
        transaction.update(counterRef, {
          'lastSequence': sequence,
          'lastCardNumber': cardNumber,
        });
      } else {
        transaction.set(counterRef, {
          'lastSequence': sequence,
          'lastCardNumber': cardNumber,
        });
      }
      return cardNumber;
    });
  }

  Future<void> markMemberCardRequestReadyAtPos({
    required String requestId,
    required String memberCardNumber,
    required String managerUid,
  }) async {
    final requestRef =
        _firestore.collection('memberCardRequests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final data = requestSnapshot.data();
      if (!requestSnapshot.exists ||
          data?['status'] != 'issued_pending_print' ||
          data?['memberCardNumber'] != memberCardNumber ||
          data?['issuedBy'] != managerUid) {
        throw StateError(
          'La solicitud no coincide con la Member Card emitida.',
        );
      }
      transaction.update(requestRef, {
        'status': 'ready_at_pos',
        'sentToPosAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<String> resolveUserUid(String memberCardNumber) async {
    final cardNumber = memberCardNumber.trim();
    if (RegExp(r'^CW-\d{6}$').hasMatch(cardNumber)) {
      return _resolveMemberCardUserUid(cardNumber);
    }
    if (RegExp(r'^WLV-M-\d{6}$').hasMatch(cardNumber)) {
      return _resolvePaidMemberCardUserUid(cardNumber);
    }
    return memberCardNumber;
  }

  Future<String> resolveMemberCardUserUid(String memberCardNumber) async {
    final cardNumber = memberCardNumber.trim();
    if (!RegExp(r'^(CW-\d{6}|WLV-M-\d{6})$').hasMatch(cardNumber)) {
      throw const FormatException(
        'Ingresa un ID Member Card válido o el contenido de su QR.',
      );
    }
    return RegExp(r'^WLV-M-\d{6}$').hasMatch(cardNumber)
        ? _resolvePaidMemberCardUserUid(cardNumber)
        : _resolveMemberCardUserUid(cardNumber);
  }

  Future<String> _resolveMemberCardUserUid(String cardNumber) async {
    final lookup =
        await _firestore.collection('memberCardLookups').doc(cardNumber).get();
    final lookupData = lookup.data();
    final userUid = lookupData?['userUid'];
    final sequence = lookupData?['sequence'];
    if (!lookup.exists ||
        userUid is! String ||
        userUid.isEmpty ||
        sequence is! int ||
        lookupData?['cardNumber'] != cardNumber) {
      throw StateError(
        'No existe la Wolves Member Card $cardNumber. El miembro debe emitir '
        'su tarjeta desde la sección Wolves Member Card.',
      );
    }

    final card = await _firestore.collection('memberCards').doc(userUid).get();
    final cardData = card.data();
    if (!card.exists ||
        cardData?['userUid'] != userUid ||
        cardData?['cardNumber'] != cardNumber ||
        cardData?['sequence'] != sequence) {
      throw StateError(
        'La Member Card $cardNumber no está activa o no coincide con su registro.',
      );
    }

    return userUid;
  }

  Future<String> _resolvePaidMemberCardUserUid(String cardNumber) async {
    final lookup =
        await _firestore.collection('memberCardLookups').doc(cardNumber).get();
    final lookupData = lookup.data();
    final userUid = lookupData?['userUid'];
    final sequence = lookupData?['sequence'];
    if (!lookup.exists ||
        userUid is! String ||
        userUid.isEmpty ||
        lookupData?['cardNumber'] != cardNumber ||
        sequence is! int) {
      throw StateError('No existe una Member Card activa con ID $cardNumber.');
    }

    final card =
        await _firestore.collection('wolves_member_card').doc(userUid).get();
    final cardData = card.data();
    if (!card.exists ||
        cardData?['userUid'] != userUid ||
        cardData?['memberCardNumber'] != cardNumber ||
        cardData?['sequence'] != sequence ||
        cardData?['status'] != 'active') {
      throw StateError('La Member Card $cardNumber no está activa.');
    }
    return userUid;
  }
}
