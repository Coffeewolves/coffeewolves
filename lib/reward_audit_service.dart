import 'package:cloud_firestore/cloud_firestore.dart';
import 'collectible_models.dart';

class ColdBrewFigure {
  const ColdBrewFigure({required this.id, required this.name});

  final String id;
  final String name;
}

const coldBrewFigures = <ColdBrewFigure>[
  ColdBrewFigure(id: 'classic', name: 'Cold Brew'),
  ColdBrewFigure(id: 'orange', name: 'Orange Cold Brew'),
  ColdBrewFigure(id: 'nitro', name: 'Nitro Cold Brew'),
  ColdBrewFigure(id: 'wolves_milk', name: 'Wolves Milk Cold Brew'),
  ColdBrewFigure(id: 'orange_milk', name: 'Orange Milk Cold Brew'),
  ColdBrewFigure(id: 'berry_milk', name: 'Berry Milk Cold Brew'),
  ColdBrewFigure(id: 'pineapple_milk', name: 'Pineapple Milk Cold Brew'),
  ColdBrewFigure(id: 'coconut_milk', name: 'Coconut Milk Cold Brew'),
  ColdBrewFigure(
      id: 'passion_fruit_milk', name: 'Passion Fruit Milk Cold Brew'),
  ColdBrewFigure(id: 'peach_milk', name: 'Peach Milk Cold Brew'),
  ColdBrewFigure(id: 'vanilla_milk', name: 'Vanilla Milk Cold Brew'),
  ColdBrewFigure(id: 'copoazu_milk', name: 'Copoazu Milk Cold Brew'),
  ColdBrewFigure(id: 'lemon_milk', name: 'Lemon Milk Cold Brew'),
  ColdBrewFigure(id: 'blackberry_milk', name: 'Blackberry Milk Cold Brew'),
  ColdBrewFigure(id: 'apple_milk', name: 'Apple Milk Cold Brew'),
  ColdBrewFigure(id: 'lulo_milk', name: 'Lulo Milk Cold Brew'),
];

class CollectibleUnitRegistration {
  const CollectibleUnitRegistration({
    required this.modelCode,
    required this.character,
    required this.serial,
    required this.code,
  });

  final String modelCode;
  final String character;
  final int serial;
  final String code;
}

class CollectibleAdoptionRecord {
  const CollectibleAdoptionRecord({
    required this.code,
    required this.modelCode,
    required this.serial,
    required this.character,
    required this.ownerUid,
    required this.ownerName,
  });

  final String code;
  final String modelCode;
  final String serial;
  final String character;
  final String? ownerUid;
  final String? ownerName;
}

class RewardAuditService {
  RewardAuditService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> stampPassportMethod({
    required String customerUid,
    required String employeeUid,
    required String employeeEmail,
    required String methodName,
    required List<String> validMethodNames,
  }) async {
    if (!validMethodNames.contains(methodName)) {
      throw ArgumentError.value(methodName, 'methodName', 'Método no válido.');
    }
    final progressRef =
        _firestore.collection('passportProgress').doc(customerUid);
    final stampRef = _firestore.collection('passportMethodStamps').doc();

    return _firestore.runTransaction((transaction) async {
      final progress = await transaction.get(progressRef);
      final data = progress.data();
      final completedMethods =
          (data?['completedMethods'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      if (completedMethods.contains(methodName)) {
        throw StateError('Ese método ya fue validado para este cliente.');
      }
      if (data?['rewardClaimed'] == true) {
        throw StateError('Este Passport ya recibió su taza legendaria.');
      }
      final updatedMethods = [...completedMethods, methodName];
      final now = FieldValue.serverTimestamp();
      final progressData = {
        'customerUid': customerUid,
        'completedMethods': updatedMethods,
        'completedCount': updatedMethods.length,
        'rewardClaimed': false,
        'updatedBy': employeeUid,
        'updatedAt': now,
        'lastStampId': stampRef.id,
        if (!progress.exists) 'createdAt': now,
      };
      if (progress.exists) {
        transaction.update(progressRef, progressData);
      } else {
        transaction.set(progressRef, progressData);
      }
      transaction.set(stampRef, {
        'customerUid': customerUid,
        'employeeUid': employeeUid,
        'employeeEmail': employeeEmail,
        'methodName': methodName,
        'stampedAt': now,
      });
    });
  }

  Future<void> redeemLegendaryMug({
    required String customerUid,
    required String employeeUid,
    required String employeeEmail,
    required String mugCode,
    required List<String> requiredMethodNames,
  }) async {
    if (requiredMethodNames.length != 9 ||
        requiredMethodNames.toSet().length != 9) {
      throw ArgumentError.value(
        requiredMethodNames,
        'requiredMethodNames',
        'El Passport debe contener exactamente nueve métodos únicos.',
      );
    }
    final normalizedCode = mugCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{4,80}$').hasMatch(normalizedCode)) {
      throw ArgumentError.value(
        mugCode,
        'mugCode',
        'El código debe tener de 4 a 80 letras, números o guiones.',
      );
    }
    final progressRef =
        _firestore.collection('passportProgress').doc(customerUid);
    final redemptionRef =
        _firestore.collection('legendaryMugRedemptions').doc(normalizedCode);

    return _firestore.runTransaction((transaction) async {
      final progress = await transaction.get(progressRef);
      final redemption = await transaction.get(redemptionRef);
      if (!progress.exists) {
        throw StateError('El cliente no tiene un Passport registrado.');
      }
      final data = progress.data()!;
      final completedCount = (data['completedCount'] as num?)?.toInt() ?? 0;
      final completedMethods =
          (data['completedMethods'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
      final requiredMethods = requiredMethodNames.toSet();
      if (completedCount != requiredMethodNames.length ||
          completedMethods.length != requiredMethods.length ||
          !completedMethods.containsAll(requiredMethods)) {
        throw StateError(
          'El cliente debe completar exactamente los 9 métodos del Passport ($completedCount/${requiredMethodNames.length}).',
        );
      }
      if (data['rewardClaimed'] == true) {
        throw StateError('Este cliente ya recibió su taza legendaria.');
      }
      if (redemption.exists) {
        throw StateError('El código de taza ya fue registrado.');
      }

      final now = FieldValue.serverTimestamp();
      transaction.update(progressRef, {
        'rewardClaimed': true,
        'rewardMugCode': normalizedCode,
        'rewardClaimedBy': employeeUid,
        'rewardClaimedAt': now,
      });
      transaction.set(redemptionRef, {
        'customerUid': customerUid,
        'employeeUid': employeeUid,
        'employeeEmail': employeeEmail,
        'mugCode': normalizedCode,
        'redeemedAt': now,
      });
    });
  }

  Future<void> redeemColdBrewStamp({
    required String customerUid,
    required String employeeUid,
    required String employeeEmail,
    required String qrId,
    required String figureId,
    required double distanceMeters,
  }) async {
    if (!RegExp(r'^coffee-wolves:cold-brew:[A-Za-z0-9_=-]+:\d+$')
        .hasMatch(qrId)) {
      throw ArgumentError.value(qrId, 'qrId', 'El QR de canje no es válido.');
    }
    if (!coldBrewFigures.any((figure) => figure.id == figureId)) {
      throw ArgumentError.value(
        figureId,
        'figureId',
        'La figurita de Cold Brew no es válida.',
      );
    }
    if (!distanceMeters.isFinite || distanceMeters < 0 || distanceMeters > 50) {
      throw ArgumentError.value(
        distanceMeters,
        'distanceMeters',
        'La distancia debe ser un valor entre 0 y 50 metros.',
      );
    }
    final albumRef = _firestore.collection('coldBrewAlbums').doc(customerUid);
    final auditRef = _firestore.collection('rewardRedemptions').doc(qrId);

    return _firestore.runTransaction((transaction) async {
      final album = await transaction.get(albumRef);
      final existingRedemption = await transaction.get(auditRef);
      if (existingRedemption.exists) {
        throw StateError('Este QR ya fue canjeado y marcado como entregado.');
      }
      final stamps = (album.data()?['stamps'] as num?)?.toInt() ?? 0;
      final collectedFigures = (album.data()?['figures'] as List<dynamic>? ??
              const [])
          .whereType<String>()
          .toSet()
        ..add(figureId);
      final figures = coldBrewFigures
          .where((figure) => collectedFigures.contains(figure.id))
          .map((figure) => figure.id)
          .toList(growable: false);
      final redemption = _auditData(
        customerUid: customerUid,
        employeeUid: employeeUid,
        employeeEmail: employeeEmail,
        rewardType: 'coldBrewStamp',
        rewardId: qrId,
      )
        ..['distanceMeters'] = distanceMeters
        ..['figureId'] = figureId
        ..['status'] = 'delivered';

      transaction.set(auditRef, redemption);
      transaction.set(albumRef, {
        'customerUid': customerUid,
        'stamps': stamps + 1,
        'figures': figures,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': employeeUid,
        'lastRedemptionId': auditRef.id,
      });
    });
  }

  Future<List<CollectibleUnitRegistration>> registerCollectible({
    required String modelCode,
    required String character,
    required int quantity,
    required String employeeUid,
  }) async {
    if (!isValidCollectibleModel(modelCode) ||
        collectibleModelNames[modelCode] != character ||
        quantity < 1 ||
        quantity > 100) {
      throw ArgumentError(
        'Indica un modelo oficial con su nombre registrado y una cantidad entre 1 y 100.',
      );
    }
    final registrations = <CollectibleUnitRegistration>[];
    var remaining = quantity;
    while (remaining > 0) {
      final batchSize = remaining > 8 ? 8 : remaining;
      try {
        registrations.addAll(
          await _registerCollectibleBatch(
            modelCode: modelCode,
            character: character,
            quantity: batchSize,
            employeeUid: employeeUid,
          ),
        );
      } catch (error) {
        if (registrations.isEmpty) rethrow;
        throw StateError(
          'Se registraron ${registrations.length} de $quantity unidades. '
          'Corrige el problema y continúa con el siguiente número: $error',
        );
      }
      remaining -= batchSize;
    }
    return registrations;
  }

  Future<List<CollectibleUnitRegistration>> _registerCollectibleBatch({
    required String modelCode,
    required String character,
    required int quantity,
    required String employeeUid,
  }) async {
    final counterRef =
        _firestore.collection('collectiblePlushCounters').doc(modelCode);
    final collectibleCollection = _firestore.collection('collectiblePlushes');
    return _firestore.runTransaction((transaction) async {
      final counter = await transaction.get(counterRef);
      final lastSequence = counter.data()?['lastSequence'];
      if (counter.exists && (lastSequence is! int || lastSequence < 0)) {
        throw const FormatException(
          'El contador de este modelo de peluche no es válido.',
        );
      }
      final firstSerial = counter.exists ? (lastSequence as int) + 1 : 1;
      final lastSerial = firstSerial + quantity - 1;
      if (lastSerial > 9999) {
        throw StateError(
          'Se agotaron los números de serie disponibles para $modelCode.',
        );
      }

      final units = List.generate(quantity, (index) {
        final serial = firstSerial + index;
        final serialCode = serial.toString().padLeft(4, '0');
        final code = '$modelCode-$serialCode';
        return (
          serial: serial,
          serialCode: serialCode,
          code: code,
          reference: collectibleCollection.doc(code),
          publicReference: _firestore.collection('plushAuthenticity').doc(code),
        );
      }, growable: false);
      final existingUnits = <String>[];
      for (final unit in units) {
        final existing = await transaction.get(unit.reference);
        final publicEntry = await transaction.get(unit.publicReference);
        if (existing.exists || publicEntry.exists) {
          existingUnits.add(unit.code);
        }
      }
      if (existingUnits.isNotEmpty) {
        throw StateError(
          'Ya existe una unidad con serie ${existingUnits.join(', ')}. '
          'No se registró ninguna unidad del lote.',
        );
      }

      final createdAt = FieldValue.serverTimestamp();
      final historyCollection = _firestore.collection('plushUnitHistory');
      final characterRef =
          _firestore.collection('collectibleCharacters').doc(modelCode);
      final characterSnapshot = await transaction.get(characterRef);
      if (characterSnapshot.exists &&
          characterSnapshot.data()?['name'] != character) {
        throw StateError(
          'El código $modelCode ya pertenece a otro personaje.',
        );
      }
      if (!characterSnapshot.exists) {
        transaction.set(characterRef, {
          'modelCode': modelCode,
          'name': character,
          'edition': 'Original Collection',
          'createdAt': createdAt,
          'createdBy': employeeUid,
        });
      }
      for (final unit in units) {
        transaction.set(unit.reference, {
          'code': unit.code,
          'modelCode': modelCode,
          'character': character,
          'serial': unit.serialCode,
          'sequence': unit.serial,
          'edition': 'Original Collection',
          'inventoryStatus': 'IN_STOCK',
          'createdBy': employeeUid,
          'createdAt': createdAt,
          'claimedBy': null,
          'claimedAt': null,
          'claimedByEmployee': null,
        });
        transaction.set(unit.publicReference, {
          'code': unit.code,
          'modelCode': modelCode,
          'character': character,
          'serial': unit.serialCode,
          'sequence': unit.serial,
          'edition': 'Original Collection',
          'status': 'available',
          'registeredAt': createdAt,
          'adoptedAt': null,
        });
        final historyRef = historyCollection.doc();
        transaction.set(historyRef, {
          'code': unit.code,
          'modelCode': modelCode,
          'action': 'registered',
          'employeeUid': employeeUid,
          'createdAt': createdAt,
        });
      }
      if (counter.exists) {
        transaction.update(counterRef, {'lastSequence': lastSerial});
      } else {
        transaction.set(counterRef, {'lastSequence': lastSerial});
      }
      return units
          .map(
            (unit) => CollectibleUnitRegistration(
              modelCode: modelCode,
              character: character,
              serial: unit.serial,
              code: unit.code,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<CollectibleAdoptionRecord> adoptCollectible({
    required String code,
    required String employeeUid,
    required String employeeEmail,
    String? ownerUid,
    String? ownerName,
    String? saleId,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    final collectibleRef =
        _firestore.collection('collectiblePlushes').doc(normalizedCode);
    final publicRef =
        _firestore.collection('plushAuthenticity').doc(normalizedCode);
    final adoptionRef =
        _firestore.collection('plushAdoptions').doc(normalizedCode);
    final certificateRef =
        _firestore.collection('plushCertificates').doc(normalizedCode);
    final normalizedSaleId = saleId?.trim();
    final saleRef = normalizedSaleId == null || normalizedSaleId.isEmpty
        ? null
        : _firestore.collection('cafeSales').doc(normalizedSaleId);

    return _firestore.runTransaction((transaction) async {
      final collectible = await transaction.get(collectibleRef);
      final publicRecord = await transaction.get(publicRef);
      final adoption = await transaction.get(adoptionRef);
      final certificate = await transaction.get(certificateRef);
      final sale = saleRef == null ? null : await transaction.get(saleRef);
      if (!collectible.exists || !publicRecord.exists) {
        throw StateError('La unidad no existe en el registro de autenticidad.');
      }
      if (collectible.data()?['claimedBy'] != null ||
          publicRecord.data()?['status'] != 'available' ||
          (collectible.data()?['inventoryStatus'] != null &&
              collectible.data()?['inventoryStatus'] != 'IN_STOCK') ||
          adoption.exists ||
          certificate.exists) {
        throw StateError('Esta unidad ya fue adoptada.');
      }
      if (saleRef != null && sale?.exists != true) {
        throw StateError('No existe la venta indicada para esta adopción.');
      }

      final adoptedAt = FieldValue.serverTimestamp();
      transaction.update(collectibleRef, {
        'claimedBy': ownerUid,
        'claimedByName':
            ownerName?.trim().isNotEmpty == true ? ownerName!.trim() : null,
        'claimedAt': adoptedAt,
        'claimedByEmployee': employeeUid,
        'inventoryStatus': 'ADOPTED',
      });
      transaction.update(publicRef, {
        'status': 'adopted',
        'adoptedAt': adoptedAt,
      });
      transaction.set(adoptionRef, {
        'code': normalizedCode,
        'modelCode': collectible.data()?['modelCode'],
        'serial': collectible.data()?['serial'],
        'sequence': collectible.data()?['sequence'],
        'character': collectible.data()?['character'],
        'ownerUid': ownerUid,
        'ownerName':
            ownerName?.trim().isNotEmpty == true ? ownerName!.trim() : null,
        'employeeUid': employeeUid,
        'employeeEmail': employeeEmail,
        'adoptedAt': adoptedAt,
        if (normalizedSaleId != null && normalizedSaleId.isNotEmpty)
          'saleId': normalizedSaleId,
      });
      transaction.set(certificateRef, {
        'certificateNumber': 'WOC-$normalizedCode',
        'code': normalizedCode,
        'modelCode': collectible.data()?['modelCode'],
        'serial': collectible.data()?['serial'],
        'sequence': collectible.data()?['sequence'],
        'character': collectible.data()?['character'],
        'edition': 'Original Collection',
        'version': 1,
        'ownerUid': ownerUid,
        'ownerName':
            ownerName?.trim().isNotEmpty == true ? ownerName!.trim() : null,
        'adoptedAt': adoptedAt,
        if (normalizedSaleId != null && normalizedSaleId.isNotEmpty)
          'saleId': normalizedSaleId,
      });
      final historyRef = _firestore.collection('plushUnitHistory').doc();
      transaction.set(historyRef, {
        'code': normalizedCode,
        'action': 'adopted',
        'employeeUid': employeeUid,
        'employeeEmail': employeeEmail,
        'ownerUid': ownerUid,
        'createdAt': adoptedAt,
        if (normalizedSaleId != null && normalizedSaleId.isNotEmpty)
          'saleId': normalizedSaleId,
      });
      return CollectibleAdoptionRecord(
        code: normalizedCode,
        modelCode: collectible.data()?['modelCode'] as String? ?? '',
        serial: collectible.data()?['serial'] as String? ?? '',
        character: collectible.data()?['character'] as String? ?? '',
        ownerUid: ownerUid,
        ownerName:
            ownerName?.trim().isNotEmpty == true ? ownerName!.trim() : null,
      );
    });
  }

  Future<void> createGiftCard({
    required String code,
    required double amount,
    required String employeeUid,
    required String employeeEmail,
  }) async {
    final cardRef = _firestore.collection('giftCards').doc(code);
    await _firestore.runTransaction((transaction) async {
      final existingCard = await transaction.get(cardRef);
      if (existingCard.exists) {
        throw StateError('Ese código de Gift Card ya existe. Genera otro.');
      }
      transaction.set(cardRef, {
        'code': code,
        'initialBalance': amount,
        'balance': amount,
        'status': 'active',
        'createdBy': employeeUid,
        'createdByEmail': employeeEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'redeemedBy': null,
        'redeemedAt': null,
        'lastRedemptionId': null,
      });
    });
  }

  Future<double> redeemGiftCard({
    required String code,
    required String customerUid,
  }) async {
    if (customerUid.isEmpty || customerUid.contains('/')) {
      throw ArgumentError.value(
        customerUid,
        'customerUid',
        'Debe ser un UID válido.',
      );
    }
    final cardRef = _firestore.collection('giftCards').doc(code);
    final walletRef = _firestore.collection('wallets').doc(customerUid);
    final walletTransactionRef =
        _firestore.collection('walletTransactions').doc();
    var walletBalanceAfter = 0.0;

    await _firestore.runTransaction((transaction) async {
      final card = await transaction.get(cardRef);
      final wallet = await transaction.get(walletRef);
      final data = card.data();
      if (!card.exists || data == null || data['status'] != 'active') {
        throw StateError('La Gift Card no existe o ya fue canjeada.');
      }
      final balance = data['balance'];
      if (balance is! num || balance <= 0) {
        throw StateError('La Gift Card no tiene saldo disponible.');
      }
      final currentWallet = wallet.data();
      final currentBalance = currentWallet?['balance'];
      if (wallet.exists &&
          (currentWallet?['ownerUid'] != customerUid ||
              currentBalance is! num ||
              currentBalance < 0)) {
        throw StateError('La billetera del cliente no es válida.');
      }
      final walletBalanceBefore =
          wallet.exists ? (currentBalance as num).toDouble() : 0.0;
      final credit = balance.toDouble();
      walletBalanceAfter = walletBalanceBefore + credit;
      final now = FieldValue.serverTimestamp();
      transaction.update(cardRef, {
        'balance': 0,
        'status': 'redeemed',
        'redeemedBy': customerUid,
        'redeemedAt': now,
        'lastRedemptionId': walletTransactionRef.id,
      });
      transaction.set(walletRef, {
        'ownerUid': customerUid,
        'balance': walletBalanceAfter,
        'updatedAt': now,
        'lastTransactionId': walletTransactionRef.id,
      });
      transaction.set(walletTransactionRef, {
        'ownerUid': customerUid,
        'type': 'giftCardRedemption',
        'direction': 'credit',
        'amount': credit,
        'balanceBefore': walletBalanceBefore,
        'balanceAfter': walletBalanceAfter,
        'giftCardCode': code,
        'createdAt': now,
      });
    });
    return walletBalanceAfter;
  }

  Future<double> getWalletBalance(String customerUid) async {
    if (customerUid.isEmpty || customerUid.contains('/')) {
      throw ArgumentError.value(
        customerUid,
        'customerUid',
        'Debe ser un UID válido.',
      );
    }
    final wallet =
        await _firestore.collection('wallets').doc(customerUid).get();
    if (!wallet.exists) return 0;
    final data = wallet.data();
    final balance = data?['balance'];
    if (data?['ownerUid'] != customerUid || balance is! num || balance < 0) {
      throw StateError('La billetera guardada no es válida.');
    }
    return balance.toDouble();
  }

  Map<String, dynamic> _auditData({
    required String customerUid,
    required String employeeUid,
    required String employeeEmail,
    required String rewardType,
    required String rewardId,
  }) {
    return {
      'customerUid': customerUid,
      'employeeUid': employeeUid,
      'employeeEmail': employeeEmail,
      'rewardType': rewardType,
      'rewardId': rewardId,
      'redeemedAt': FieldValue.serverTimestamp(),
    };
  }
}
