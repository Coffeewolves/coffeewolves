import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'product_catalog_service.dart';

String customerComplaintAutoReply(String feedbackType) =>
    switch (feedbackType) {
      'suggestion' =>
        'Gracias por compartir tu sugerencia. Gerencia la recibió y la revisará.',
      'compliment' =>
        'Gracias por tu felicitación. Nos alegra compartir la experiencia Coffee Wolves contigo.',
      'complaint' =>
        'Recibimos tu reclamo. Gerencia revisará el caso y podrás consultar aquí su estado.',
      _ => throw ArgumentError.value(
          feedbackType,
          'feedbackType',
          'Tipo de mensaje no válido.',
        ),
    };

String customerComplaintStatusMessage(String status) => switch (status) {
      'new' => 'Tu mensaje fue recibido y está pendiente de revisión.',
      'reviewing' =>
        'Gerencia está revisando tu mensaje. Te avisaremos aquí cuando haya una actualización.',
      'resolved' =>
        'Gerencia marcó tu caso como resuelto. Si aún necesitas ayuda, envía otro mensaje.',
      _ => throw ArgumentError.value(
          status,
          'status',
          'Estado de mensaje no válido.',
        ),
    };

class BusinessOperationsService {
  BusinessOperationsService(this._firestore);

  final FirebaseFirestore _firestore;

  String dateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String assignmentId(String date, String employeeUid) =>
      '${date}_$employeeUid';

  String attendanceId(String date, String employeeUid) =>
      '${date}_$employeeUid';

  String cashSessionId(String date, String employeeUid, String shift) =>
      '${date}_${employeeUid}_$shift';

  Future<void> assignShift({
    required String employeeUid,
    required String employeeEmail,
    required DateTime date,
    required String shift,
    required String managerUid,
  }) async {
    if (!const {'morning', 'afternoon'}.contains(shift)) {
      throw ArgumentError.value(
        shift,
        'shift',
        'Selecciona el turno de mañana o tarde.',
      );
    }
    final key = dateKey(date);
    await _firestore
        .collection('staffShifts')
        .doc(assignmentId(key, employeeUid))
        .set({
      'employeeUid': employeeUid,
      'employeeEmail': employeeEmail,
      'date': key,
      'shift': shift,
      'assignedBy': managerUid,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clockIn({
    required String employeeUid,
    required DateTime date,
    required String shift,
  }) async {
    final key = dateKey(date);
    final id = attendanceId(key, employeeUid);
    final attendanceRef = _firestore.collection('staffAttendance').doc(id);
    final assignmentRef = _firestore
        .collection('staffShifts')
        .doc(assignmentId(key, employeeUid));

    await _firestore.runTransaction((transaction) async {
      final assignment = await transaction.get(assignmentRef);
      final attendance = await transaction.get(attendanceRef);
      if (!assignment.exists || assignment.data()?['shift'] != shift) {
        throw StateError('No tienes ese turno asignado para hoy.');
      }
      if (attendance.exists) {
        throw StateError('Ya registraste tu entrada para este día.');
      }

      transaction.set(attendanceRef, {
        'employeeUid': employeeUid,
        'date': key,
        'shift': shift,
        'clockInAt': FieldValue.serverTimestamp(),
        'clockOutAt': null,
      });
    });
  }

  Future<void> clockOut({
    required String employeeUid,
    required DateTime date,
  }) async {
    final key = dateKey(date);
    final attendanceRef = _firestore
        .collection('staffAttendance')
        .doc(attendanceId(key, employeeUid));

    await _firestore.runTransaction((transaction) async {
      final attendance = await transaction.get(attendanceRef);
      if (!attendance.exists || attendance.data()?['clockOutAt'] != null) {
        throw StateError('No hay una entrada abierta para cerrar.');
      }
      final shift = attendance.data()?['shift'] as String?;
      if (shift == null) {
        throw StateError('El turno de asistencia no es válido.');
      }
      final cashRef = _firestore
          .collection('cashSessions')
          .doc(cashSessionId(key, employeeUid, shift));
      final cashSession = await transaction.get(cashRef);
      if (!cashSession.exists || cashSession.data()?['status'] != 'closed') {
        throw StateError('Cierra y arquea la caja antes de registrar salida.');
      }
      transaction.update(attendanceRef, {
        'clockOutAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> openCashSession({
    required String employeeUid,
    required DateTime date,
    required String shift,
    required double openingAmount,
  }) async {
    final key = dateKey(date);
    final sessionRef = _firestore
        .collection('cashSessions')
        .doc(cashSessionId(key, employeeUid, shift));
    final attendanceRef = _firestore
        .collection('staffAttendance')
        .doc(attendanceId(key, employeeUid));

    await _firestore.runTransaction((transaction) async {
      final session = await transaction.get(sessionRef);
      final attendance = await transaction.get(attendanceRef);
      if (session.exists) {
        throw StateError('Ya existe una caja para este turno.');
      }
      if (!attendance.exists || attendance.data()?['clockOutAt'] != null) {
        throw StateError('Registra tu entrada antes de abrir caja.');
      }
      transaction.set(sessionRef, {
        'employeeUid': employeeUid,
        'date': key,
        'shift': shift,
        'openingAmount': openingAmount,
        'openedAt': FieldValue.serverTimestamp(),
        'status': 'open',
        'closedAt': null,
        'countedAmount': null,
        'closedBy': null,
      });
    });
  }

  Future<void> closeCashSession({
    required String employeeUid,
    required DateTime date,
    required String shift,
    required double countedAmount,
  }) async {
    final sessionRef = _firestore
        .collection('cashSessions')
        .doc(cashSessionId(dateKey(date), employeeUid, shift));

    await _firestore.runTransaction((transaction) async {
      final session = await transaction.get(sessionRef);
      if (!session.exists || session.data()?['status'] != 'open') {
        throw StateError('No hay una caja abierta para este turno.');
      }
      transaction.update(sessionRef, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'countedAmount': countedAmount,
        'closedBy': employeeUid,
      });
    });
  }

  Future<String> recordSale({
    required String employeeUid,
    required String employeeEmail,
    required DateTime date,
    required String shift,
    required String paymentMethod,
    String serviceType = 'takeaway',
    required double total,
    required double cashReceived,
    required double changeDue,
    required List<Map<String, dynamic>> items,
    required Map<String, int> trackedProducts,
    String? saleId,
    Map<String, int> trackedShopProducts = const {},
    Map<String, Map<String, int>> trackedShopVariants = const {},
    String? customerUid,
    int? tableNumber,
  }) async {
    final key = dateKey(date);
    if (saleId != null && (saleId.isEmpty || saleId.contains('/'))) {
      throw ArgumentError.value(saleId, 'saleId', 'Debe ser un ID válido.');
    }
    final saleRef = _firestore.collection('cafeSales').doc(saleId);
    final walletRef = paymentMethod == 'wallet' && customerUid != null
        ? _firestore.collection('wallets').doc(customerUid)
        : null;
    final walletTransactionRef = walletRef == null
        ? null
        : _firestore.collection('walletTransactions').doc(saleRef.id);
    final cafeItems = items
        .where((item) => item['catalogCollection'] == 'cafeCatalog')
        .toList(growable: false);
    final kitchenOrderRef =
        _firestore.collection('kitchenOrders').doc(saleRef.id);
    final attendanceRef = _firestore
        .collection('staffAttendance')
        .doc(attendanceId(key, employeeUid));
    final assignmentRef = _firestore
        .collection('staffShifts')
        .doc(assignmentId(key, employeeUid));
    final sessionRef = _firestore
        .collection('cashSessions')
        .doc(cashSessionId(key, employeeUid, shift));
    final cafeProductIds =
        cafeItems.map((item) => item['productId']).whereType<String>().toSet();
    final inventoryRefs = cafeProductIds.map(
      (productId) => _firestore.collection('cafeCatalog').doc(productId),
    );
    final shopInventoryRefs = trackedShopProducts.keys.map(
      (productId) => _firestore.collection('products').doc(productId),
    );

    return _firestore.runTransaction((transaction) async {
      final attendance = await transaction.get(attendanceRef);
      final assignment = await transaction.get(assignmentRef);
      final session = await transaction.get(sessionRef);
      final inventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final shopInventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final reference in inventoryRefs) {
        inventorySnapshots[reference.id] = await transaction.get(reference);
      }
      for (final reference in shopInventoryRefs) {
        shopInventorySnapshots[reference.id] = await transaction.get(reference);
      }

      if (!assignment.exists || assignment.data()?['shift'] != shift) {
        throw StateError('No existe una asignación vigente para este turno.');
      }
      if (!attendance.exists || attendance.data()?['clockOutAt'] != null) {
        throw StateError('Registra tu entrada antes de cobrar.');
      }
      if (!session.exists || session.data()?['status'] != 'open') {
        throw StateError('Abre la caja antes de registrar ventas.');
      }
      if (paymentMethod == 'wallet') {
        if (customerUid == null || customerUid.isEmpty || walletRef == null) {
          throw StateError(
            'Debes identificar al cliente para cobrar con billetera.',
          );
        }
      }
      for (final saleLine in cafeItems) {
        final productId = saleLine['productId'] as String?;
        final data =
            productId == null ? null : inventorySnapshots[productId]?.data();
        if (productId == null || data == null || data['isDeleted'] == true) {
          throw StateError('El producto $productId ya no está disponible.');
        }
        final catalogPrice = (data['price'] as num?)?.toDouble();
        final salePrice = (saleLine['unitPrice'] as num?)?.toDouble();
        if (data['isAvailable'] != true ||
            data['isVisible'] == false ||
            catalogPrice == null ||
            catalogPrice <= 0 ||
            catalogPrice != salePrice) {
          throw StateError(
            'El producto ${data['name'] ?? productId} no está disponible con ese precio.',
          );
        }
      }
      for (final entry in trackedProducts.entries) {
        final data = inventorySnapshots[entry.key]?.data();
        final stock = data?['stock'];
        if (data?['stockTracked'] != true ||
            stock is! int ||
            stock < entry.value) {
          throw StateError(
              'Stock insuficiente para ${data?['name'] ?? entry.key}.');
        }
      }
      for (final entry in trackedShopVariants.entries) {
        final sizes = wolvesShopSizes.toSet();
        final data = shopInventorySnapshots[entry.key]?.data();
        final rawStockBySize = data?['stockBySize'];
        if (data == null ||
            rawStockBySize is! Map ||
            entry.value.keys.any((size) => !sizes.contains(size))) {
          throw StateError('El stock por talle de ${entry.key} no es válido.');
        }
        final stockBySize = <String, int>{};
        for (final size in sizes) {
          final stock = rawStockBySize[size] ?? 0;
          if (stock is! int || stock < 0) {
            throw StateError(
                'El stock por talle de ${entry.key} no es válido.');
          }
          stockBySize[size] = stock;
        }
        final totalBySize =
            stockBySize.values.fold<int>(0, (total, stock) => total + stock);
        if (totalBySize != data['stock']) {
          throw StateError(
            'El stock total de ${entry.key} no coincide con sus tallas.',
          );
        }
        final requestedTotal = entry.value.values
            .fold<int>(0, (total, quantity) => total + quantity);
        if (requestedTotal != trackedShopProducts[entry.key]) {
          throw StateError(
            'La cantidad por talle de ${entry.key} no coincide con la venta.',
          );
        }
        for (final sizeEntry in entry.value.entries) {
          final saleLineQuantity = items
              .where(
                (item) =>
                    item['catalogCollection'] == 'products' &&
                    item['productId'] == entry.key &&
                    item['size'] == sizeEntry.key,
              )
              .fold<int>(
                0,
                (total, item) =>
                    total +
                    (item['quantity'] is int ? item['quantity'] as int : 0),
              );
          if (sizeEntry.value < 1 ||
              sizeEntry.value > stockBySize[sizeEntry.key]! ||
              saleLineQuantity != sizeEntry.value) {
            throw StateError(
              'Stock insuficiente o línea de venta inválida para ${data['name'] ?? entry.key}, talle ${sizeEntry.key}.',
            );
          }
        }
      }
      for (final entry in trackedShopProducts.entries) {
        final data = shopInventorySnapshots[entry.key]?.data();
        final stock = data?['stock'];
        if (data == null ||
            data['isVisible'] != true ||
            data['family'] != 'Merch Wolves Shop') {
          throw StateError('El artículo ${entry.key} no está disponible.');
        }
        final catalogPrice = (data['price'] as num?)?.toDouble();
        final saleLine = items.firstWhere(
          (item) =>
              item['catalogCollection'] == 'products' &&
              item['productId'] == entry.key,
          orElse: () => const <String, dynamic>{},
        );
        final salePrice = (saleLine['unitPrice'] as num?)?.toDouble();
        if (catalogPrice == null ||
            catalogPrice <= 0 ||
            catalogPrice != salePrice) {
          throw StateError(
            'El artículo ${data['name'] ?? entry.key} no está disponible con ese precio.',
          );
        }
        if (stock is! int || stock < entry.value) {
          throw StateError(
            'Stock insuficiente para ${data['name'] ?? entry.key}.',
          );
        }
        if (data['stockBySize'] is Map &&
            !trackedShopVariants.containsKey(entry.key)) {
          throw StateError(
            'Selecciona una talla para ${data['name'] ?? entry.key}.',
          );
        }
        if (data['stockBySize'] == null &&
            trackedShopVariants.containsKey(entry.key)) {
          throw StateError(
            'El producto ${data['name'] ?? entry.key} no tiene stock por talle.',
          );
        }
      }

      transaction.set(saleRef, {
        'employeeUid': employeeUid,
        'employeeEmail': employeeEmail,
        'date': key,
        'shift': shift,
        'attendanceId': attendanceId(key, employeeUid),
        'cashSessionId': cashSessionId(key, employeeUid, shift),
        'paymentMethod': paymentMethod,
        'total': total,
        'cashReceived': cashReceived,
        'changeDue': changeDue,
        'items': items,
        'cafeItems': cafeItems,
        'productQuantities': trackedProducts,
        'shopProductQuantities': trackedShopProducts,
        if (trackedShopVariants.isNotEmpty)
          'shopVariantQuantities': trackedShopVariants,
        if (walletTransactionRef != null)
          'walletTransactionId': walletTransactionRef.id,
        if (customerUid != null && customerUid.isNotEmpty)
          'customerUid': customerUid,
        'paidAt': FieldValue.serverTimestamp(),
      });

      if (cafeItems.isNotEmpty) {
        final kitchenItems = cafeItems.map((item) {
          final rawNotes = item['modifications'] ?? item['notes'];
          final modifications = rawNotes is String && rawNotes.trim().isNotEmpty
              ? [rawNotes.trim()]
              : rawNotes is List
                  ? rawNotes.whereType<String>().toList(growable: false)
                  : const <String>[];
          return {
            'quantity': item['quantity'],
            'name': item['name'],
            if (item['size'] is String) 'size': item['size'],
            'modifications': modifications,
          };
        }).toList(growable: false);

        transaction.set(kitchenOrderRef, {
          'orderId': saleRef.id,
          if (tableNumber != null) 'tableNumber': tableNumber,
          'serviceType': serviceType,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        for (var index = 0; index < kitchenItems.length; index++) {
          transaction.set(
            kitchenOrderRef.collection('items').doc('$index'),
            {
              ...kitchenItems[index],
              'position': index,
            },
          );
        }
      }

      if (walletRef != null && walletTransactionRef != null) {
        transaction.update(walletRef, {
          'balance': FieldValue.increment(-total),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastTransactionId': walletTransactionRef.id,
        });
        transaction.set(walletTransactionRef, {
          'ownerUid': customerUid,
          'type': 'posDebit',
          'direction': 'debit',
          'amount': total,
          'saleId': saleRef.id,
          'employeeUid': employeeUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      for (final entry in trackedProducts.entries) {
        final reference = _firestore.collection('cafeCatalog').doc(entry.key);
        final data = inventorySnapshots[entry.key]!.data()!;
        transaction.update(reference, {
          'stock': (data['stock'] as int) - entry.value,
          'lastSaleId': saleRef.id,
        });
      }
      for (final entry in trackedShopProducts.entries) {
        final reference = _firestore.collection('products').doc(entry.key);
        final data = shopInventorySnapshots[entry.key]!.data()!;
        final variantQuantities = trackedShopVariants[entry.key];
        final updatedStockBySize = variantQuantities == null
            ? null
            : Map<String, int>.from(data['stockBySize'] as Map);
        if (variantQuantities != null && updatedStockBySize != null) {
          for (final variant in variantQuantities.entries) {
            updatedStockBySize[variant.key] =
                updatedStockBySize[variant.key]! - variant.value;
          }
        }
        transaction.update(reference, {
          'stock': (data['stock'] as int) - entry.value,
          if (updatedStockBySize != null) 'stockBySize': updatedStockBySize,
          'lastSaleId': saleRef.id,
        });
      }
      return saleRef.id;
    });
  }

  Future<void> saveCatalogProduct({
    required String productId,
    required String name,
    required String category,
    required String description,
    required int stock,
    required bool isAvailable,
    required bool isVisible,
    required bool isDeleted,
    required String managerUid,
    required double price,
    bool stockTracked = false,
    String? familyId,
    String? familyName,
    String? imageUrl,
    bool? hasImage,
    Uint8List? imageBytes,
    bool updateExisting = false,
    bool inventorySource = false,
  }) async {
    if (productId.isEmpty ||
        name.trim().isEmpty ||
        category.trim().isEmpty ||
        stock < 0 ||
        !price.isFinite ||
        price < 0) {
      throw ArgumentError(
          'El producto debe tener ID, datos, precio y stock válidos.');
    }
    final batch = _firestore.batch();
    final productReference =
        _firestore.collection('cafeCatalog').doc(productId);
    final productData = {
      'name': name,
      'category': category,
      'description': description,
      'price': price,
      'stock': stock,
      'stockTracked': stockTracked,
      'isAvailable': isAvailable,
      'isVisible': isVisible,
      'isDeleted': isDeleted,
      if (familyId != null) 'familyId': familyId,
      if (familyName != null) 'familyName': familyName,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (hasImage != null) 'hasImage': hasImage,
      if (inventorySource) 'inventorySource': 'products',
      'updatedBy': managerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (updateExisting) {
      batch.update(productReference, productData);
    } else {
      batch.set(productReference, productData, SetOptions(merge: true));
    }
    if (imageBytes != null) {
      batch.set(
        _firestore.collection('cafeMenuImages').doc(productId),
        {
          'imageBase64': base64Encode(imageBytes),
          'contentType': 'image/jpeg',
          'updatedBy': managerUid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
  }

  Future<String> submitComplaint({
    required String customerUid,
    required String customerEmail,
    required String shift,
    required String feedbackType,
    required String incident,
    String? supportCategory,
    String? subject,
    required String details,
    String? memberCardId,
    String? orderId,
    String? attachmentBase64,
    String? attachmentName,
  }) async {
    final normalizedSubject = subject?.trim();
    final normalizedMemberCardId = memberCardId?.trim();
    if (normalizedSubject != null &&
        (normalizedSubject.length < 4 || normalizedSubject.length > 120)) {
      throw ArgumentError('El asunto debe tener entre 4 y 120 caracteres.');
    }
    if (normalizedMemberCardId != null && normalizedMemberCardId.length > 120) {
      throw ArgumentError('El ID de Wolves Member Card no es válido.');
    }
    if (supportCategory != null &&
        !const {
          'Mi Bitácora',
          'Wolves Member Card',
          'Billetera',
          'Mis Colecciones',
          'Mis Coleccionables',
          'Álbum Cold Brew',
          'Wolves Match',
          'Hoy nos falta uno',
          'Mis Mascotas',
          'Mis Pedidos',
          'Otro',
        }.contains(supportCategory)) {
      throw ArgumentError.value(
        supportCategory,
        'supportCategory',
        'Categoría de soporte no válida.',
      );
    }
    if (attachmentBase64 != null &&
        (attachmentBase64.length > 600000 ||
            attachmentName == null ||
            attachmentName.length > 120)) {
      throw ArgumentError('La captura adjunta no es válida.');
    }
    final autoReply = customerComplaintAutoReply(feedbackType);
    final complaint = _firestore.collection('customerComplaints').doc();
    await complaint.set({
      'customerUid': customerUid,
      'customerEmail': customerEmail,
      'shift': shift,
      'feedbackType': feedbackType,
      'incident': incident,
      if (supportCategory != null) 'supportCategory': supportCategory,
      if (normalizedSubject != null) 'subject': normalizedSubject,
      if (normalizedMemberCardId?.isNotEmpty == true)
        'memberCardId': normalizedMemberCardId,
      'details': details,
      'autoReply': autoReply,
      'statusMessage': customerComplaintStatusMessage('new'),
      if (attachmentBase64 != null) ...{
        'attachmentBase64': attachmentBase64,
        'attachmentContentType': 'image/jpeg',
        'attachmentName': attachmentName,
      },
      if (orderId != null && orderId.trim().isNotEmpty)
        'orderId': orderId.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'new',
    });
    return complaint.id;
  }

  Future<String> sendManagementMessage({
    required String senderUid,
    required String senderEmail,
    required String senderName,
    required String category,
    required String priority,
    required String title,
    required String body,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    if (senderUid.isEmpty ||
        senderEmail.trim().isEmpty ||
        normalizedTitle.length < 4 ||
        normalizedTitle.length > 120 ||
        normalizedBody.length < 8 ||
        normalizedBody.length > 3000 ||
        !const {'communication', 'directive'}.contains(category) ||
        !const {'normal', 'high'}.contains(priority)) {
      throw ArgumentError('Completa los datos del mensaje interno.');
    }

    final message = _firestore.collection('managementMessages').doc();
    await message.set({
      'senderUid': senderUid,
      'senderEmail': senderEmail.trim(),
      'senderName': senderName.trim(),
      'category': category,
      'priority': priority,
      'title': normalizedTitle,
      'body': normalizedBody,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return message.id;
  }

  Future<void> saveColdBrewTastingNote({
    required String customerUid,
    required String flavorProfile,
    required int rating,
  }) async {
    await _firestore.collection('coldBrewTastingNotes').add({
      'customerUid': customerUid,
      'flavorProfile': flavorProfile,
      'rating': rating,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
