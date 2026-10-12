import 'package:cloud_firestore/cloud_firestore.dart';

class MemberCardService {
  MemberCardService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<String> registerMemberCardHolder({
    required String fullName,
    required String phone,
    required String nationalId,
    required String email,
    required String createdByUid,
  }) async {
    final name = fullName.trim();
    final contactPhone = phone.trim();
    final idNumber = nationalId.trim();
    final contactEmail = email.trim().toLowerCase();
    if (name.isEmpty ||
        contactPhone.length < 8 ||
        idNumber.length < 4 ||
        contactEmail.isEmpty ||
        createdByUid.isEmpty) {
      throw ArgumentError('Completa todos los datos obligatorios del titular.');
    }

    final holderRef = _firestore.collection('member_cards').doc();
    final counterRef =
        _firestore.collection('customerMemberCardCounters').doc('current');

    return _firestore.runTransaction((transaction) async {
      final counter = await transaction.get(counterRef);
      final lastSequence = counter.data()?['lastSequence'];
      final lastCardNumber = counter.data()?['lastCardNumber'];
      if (counter.exists &&
          (lastSequence is! int ||
              lastSequence < 0 ||
              lastCardNumber is! String ||
              !RegExp(r'^CW-M-\d{6}$').hasMatch(lastCardNumber))) {
        throw const FormatException(
          'El contador de Member Card no es válido.',
        );
      }
      final sequence = counter.exists ? (lastSequence as int) + 1 : 1;
      if (sequence > 999999) {
        throw StateError('Se agotó la numeración de Member Card.');
      }

      final cardNumber = 'CW-M-${sequence.toString().padLeft(6, '0')}';
      final lookupRef =
          _firestore.collection('customerMemberCardLookups').doc(cardNumber);
      final existingLookup = await transaction.get(lookupRef);
      if (existingLookup.exists) {
        throw StateError(
          'El número $cardNumber ya está asignado. Contacta a Gerencia.',
        );
      }

      transaction.set(holderRef, {
        'fullName': name,
        'phone': contactPhone,
        'nationalId': idNumber,
        'email': contactEmail,
        'memberCardNumber': cardNumber,
        'sequence': sequence,
        'createdBy': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(lookupRef, {
        'holderId': holderRef.id,
        'cardNumber': cardNumber,
        'sequence': sequence,
        'createdBy': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (counter.exists) {
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

  Future<String> getOrCreateCardNumber(String userUid) {
    if (userUid.isEmpty || userUid.contains('/')) {
      throw ArgumentError.value(userUid, 'userUid', 'Debe ser un UID válido.');
    }

    final cardRef = _firestore.collection('memberCards').doc(userUid);
    final counterRef =
        _firestore.collection('memberCardCounters').doc('current');

    return _firestore.runTransaction((transaction) async {
      final existingCard = await transaction.get(cardRef);
      if (existingCard.exists) {
        final cardNumber = existingCard.data()?['cardNumber'];
        if (cardNumber is! String ||
            !RegExp(r'^CW-\d{6}$').hasMatch(cardNumber)) {
          throw const FormatException(
            'El número de Wolves Member Card guardado no es válido.',
          );
        }
        return cardNumber;
      }

      final counter = await transaction.get(counterRef);
      final lastSequence = counter.data()?['lastSequence'];
      if (counter.exists && (lastSequence is! int || lastSequence < 0)) {
        throw const FormatException(
          'El contador de Wolves Member Card no es válido.',
        );
      }
      final sequence = counter.exists ? (lastSequence as int) + 1 : 1;
      if (sequence > 999999) {
        throw StateError('Se agotó la numeración de Wolves Member Card.');
      }

      final cardNumber = 'CW-${sequence.toString().padLeft(6, '0')}';
      final lookupRef =
          _firestore.collection('memberCardLookups').doc(cardNumber);
      final existingLookup = await transaction.get(lookupRef);
      if (existingLookup.exists) {
        throw StateError(
          'El número $cardNumber ya está asignado. Contacta a Gerencia.',
        );
      }

      transaction.set(cardRef, {
        'userUid': userUid,
        'cardNumber': cardNumber,
        'sequence': sequence,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(lookupRef, {
        'userUid': userUid,
        'cardNumber': cardNumber,
        'sequence': sequence,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (counter.exists) {
        transaction.update(counterRef, {'lastSequence': sequence});
      } else {
        transaction.set(counterRef, {'lastSequence': sequence});
      }
      return cardNumber;
    });
  }

  Future<String> resolveUserUid(String memberCardNumber) async {
    final cardNumber = memberCardNumber.trim();
    if (!RegExp(r'^CW-\d{6}$').hasMatch(cardNumber)) {
      return memberCardNumber;
    }
    return _resolveMemberCardUserUid(cardNumber);
  }

  Future<String> resolveMemberCardUserUid(String memberCardNumber) async {
    final cardNumber = memberCardNumber.trim();
    if (!RegExp(r'^CW-\d{6}$').hasMatch(cardNumber)) {
      throw const FormatException(
        'Ingresa el ID de Member Card CW-XXXXXX o el contenido de su QR.',
      );
    }
    return _resolveMemberCardUserUid(cardNumber);
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
}
