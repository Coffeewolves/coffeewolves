import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RewardQrService {
  RewardQrService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const _passportMethods = {
    'Dripper V60',
    'Chemex',
    'Origami',
    'Aeropress',
    'Prensa francesa',
    'Sifón japonés',
    'Sifón belga',
    'Cold Brew',
    'Nitro Cold Brew',
  };

  static const _coldBrewFigures = {
    'classic',
    'orange',
    'nitro',
    'wolves_milk',
    'orange_milk',
    'berry_milk',
    'pineapple_milk',
    'coconut_milk',
    'passion_fruit_milk',
    'peach_milk',
    'vanilla_milk',
    'copoazu_milk',
    'lemon_milk',
    'blackberry_milk',
    'apple_milk',
    'lulo_milk',
  };

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<({String payload, DateTime expiresAt})> issue({
    required String rewardType,
    required String rewardId,
  }) async {
    final issuer = _requireVerifiedUser();
    _validateReward(rewardType, rewardId);

    final tokenId = _newTokenId();
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 8));
    final tokenRef = _firestore.collection('rewardQrTokens').doc(tokenId);
    await tokenRef.set({
      'rewardType': rewardType,
      'rewardId': rewardId,
      'issuerUid': issuer.uid,
      'issuerEmail': issuer.email ?? '',
      'status': 'issued',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    return (
      payload: 'coffee-wolves:reward-qr:$tokenId',
      expiresAt: expiresAt,
    );
  }

  Future<({String rewardType, String rewardId})> redeem(
    String payload, {
    String? customerUid,
  }) async {
    final actor = _requireVerifiedUser();
    final tokenId = _tokenIdFromPayload(payload);
    final isStaffRedemption = customerUid != null;
    final recipientUid = customerUid?.trim() ?? actor.uid;
    if (recipientUid.isEmpty || recipientUid.contains('/')) {
      throw ArgumentError.value(
        recipientUid,
        'customerUid',
        'El cliente no es válido.',
      );
    }
    final tokenRef = _firestore.collection('rewardQrTokens').doc(tokenId);
    final memberCardRef =
        _firestore.collection('wolves_member_card').doc(recipientUid);
    final progressRef =
        _firestore.collection('passportProgress').doc(recipientUid);
    final albumRef = _firestore.collection('coldBrewAlbums').doc(recipientUid);
    final auditRef = _firestore.collection('rewardRedemptions').doc(tokenId);
    final stampRef = _firestore.collection('passportMethodStamps').doc(tokenId);

    late String rewardType;
    late String rewardId;
    await _firestore.runTransaction((transaction) async {
      final tokenSnapshot = await transaction.get(tokenRef);
      if (!tokenSnapshot.exists) {
        throw StateError('El QR de premio no existe.');
      }
      final token = tokenSnapshot.data()!;
      rewardType = token['rewardType'] as String? ?? '';
      rewardId = token['rewardId'] as String? ?? '';
      _validateReward(rewardType, rewardId);
      if (token['status'] != 'issued') {
        throw StateError(
          'Este QR ya fue canjeado; el beneficio no se entregó otra vez.',
        );
      }
      final expiresAt = token['expiresAt'];
      if (expiresAt is! Timestamp ||
          !expiresAt.toDate().isAfter(DateTime.now())) {
        throw StateError('El QR venció. Pide al personal que emita uno nuevo.');
      }
      if (isStaffRedemption && token['issuerUid'] != actor.uid) {
        throw StateError(
          'Solo quien emitió este QR puede aplicarlo a una Member Card.',
        );
      }

      if (isStaffRedemption) {
        final memberCardSnapshot = await transaction.get(memberCardRef);
        final memberCard = memberCardSnapshot.data();
        final cardNumber = memberCard?['memberCardNumber'];
        if (!memberCardSnapshot.exists ||
            memberCard?['userUid'] != recipientUid ||
            memberCard?['status'] != 'active' ||
            cardNumber is! String ||
            !RegExp(r'^WLV-M-\d{6}$').hasMatch(cardNumber)) {
          throw StateError(
            'La Wolves Member Card del cliente no está activa.',
          );
        }
        final lookupSnapshot = await transaction.get(
          _firestore.collection('memberCardLookups').doc(cardNumber),
        );
        final lookup = lookupSnapshot.data();
        if (!lookupSnapshot.exists ||
            lookup?['userUid'] != recipientUid ||
            lookup?['cardNumber'] != cardNumber ||
            lookup?['sequence'] != memberCard?['sequence']) {
          throw StateError(
            'La Wolves Member Card del cliente no está activa.',
          );
        }
      }

      DocumentSnapshot<Map<String, dynamic>>? progressSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? albumSnapshot;
      if (rewardType == 'passportMethod') {
        progressSnapshot = await transaction.get(progressRef);
        final progress = progressSnapshot.data() ?? const <String, dynamic>{};
        final methods = (progress['completedMethods'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .toList();
        if (progress['rewardClaimed'] == true || methods.contains(rewardId)) {
          throw StateError(
            'Este método del Passport ya fue completado.',
          );
        }
      } else {
        albumSnapshot = await transaction.get(albumRef);
      }

      final issuerUid = token['issuerUid'] as String? ?? '';
      final issuerEmail = token['issuerEmail'] as String? ?? '';
      final now = FieldValue.serverTimestamp();
      final audit = <String, dynamic>{
        'customerUid': recipientUid,
        'receiverUid': recipientUid,
        'employeeUid': issuerUid,
        'employeeEmail': issuerEmail,
        'issuerUid': issuerUid,
        'issuerEmail': issuerEmail,
        'rewardType': rewardType,
        'rewardId': tokenId,
        'redeemedAt': now,
        'status': 'delivered',
        if (rewardType == 'passportMethod') 'methodName': rewardId,
        if (rewardType == 'coldBrewStamp') ...{
          'figureId': rewardId,
          'distanceMeters': 0,
        },
      };

      if (rewardType == 'passportMethod') {
        final progress = progressSnapshot!.data() ?? const <String, dynamic>{};
        final previousMethods =
            (progress['completedMethods'] as List<dynamic>? ??
                    const <dynamic>[])
                .whereType<String>()
                .toList();
        final completedMethods = [...previousMethods, rewardId];
        transaction.set(
          progressRef,
          {
            'customerUid': recipientUid,
            'completedMethods': completedMethods,
            'completedCount': completedMethods.length,
            'rewardClaimed': progress['rewardClaimed'] == true,
            'updatedBy': issuerUid,
            'updatedAt': now,
            'lastStampId': tokenId,
            if (!progressSnapshot.exists) 'createdAt': now,
          },
          SetOptions(merge: true),
        );
        transaction.set(stampRef, {
          'customerUid': recipientUid,
          'employeeUid': issuerUid,
          'employeeEmail': issuerEmail,
          'methodName': rewardId,
          'stampedAt': now,
        });
      } else {
        final album = albumSnapshot!.data() ?? const <String, dynamic>{};
        final previousFigures =
            (album['figures'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .where(_coldBrewFigures.contains)
                .toSet();
        final figures = {...previousFigures, rewardId}.toList();
        final stamps = album['stamps'];
        transaction.set(albumRef, {
          'customerUid': recipientUid,
          'stamps': (stamps is int ? stamps : 0) + 1,
          'figures': figures,
          'updatedAt': now,
          'updatedBy': issuerUid,
          'lastRedemptionId': tokenId,
        });
      }

      transaction.update(tokenRef, {
        'status': 'redeemed',
        'redeemedBy': recipientUid,
        'redeemedAt': now,
      });
      transaction.set(auditRef, audit);
    });

    return (rewardType: rewardType, rewardId: rewardId);
  }

  User _requireVerifiedUser() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      throw StateError(
        'Inicia sesión con una cuenta verificada para usar los QR de premios.',
      );
    }
    return user;
  }

  static void _validateReward(String rewardType, String rewardId) {
    if (rewardType == 'passportMethod' && _passportMethods.contains(rewardId)) {
      return;
    }
    if (rewardType == 'coldBrewStamp' && _coldBrewFigures.contains(rewardId)) {
      return;
    }
    throw ArgumentError.value(rewardId, 'rewardId', 'El premio no es válido.');
  }

  static String _tokenIdFromPayload(String payload) {
    final match = RegExp(
      r'^coffee-wolves:reward-qr:([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
      caseSensitive: false,
    ).firstMatch(payload.trim());
    if (match == null) {
      throw const FormatException('El QR de premio no es válido.');
    }
    return match.group(1)!.toLowerCase();
  }

  static String _newTokenId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
