import 'package:cloud_firestore/cloud_firestore.dart';

class MemberCardRequestService {
  MemberCardRequestService(this._firestore);

  static const settingsDocumentId = 'current';
  static const qrProductId = 'wolves-member-card';
  static const qrProductName = 'Wolves Member Card';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _firestore.collection('memberCardSettings').doc(settingsDocumentId);

  Future<double?> getPrice() async {
    final snapshot = await _settingsRef.get();
    final price = snapshot.data()?['price'];
    if (!snapshot.exists) return null;
    if (price is! num || !price.toDouble().isFinite || price <= 0) {
      throw const FormatException(
        'El precio configurado para la Member Card no es válido.',
      );
    }
    return price.toDouble();
  }

  Future<void> setPrice({
    required double price,
    required String managerUid,
  }) async {
    if (!price.isFinite || price <= 0 || managerUid.isEmpty) {
      throw ArgumentError('Ingresa un precio válido para la Member Card.');
    }
    await _settingsRef.set({
      'price': price,
      'currency': 'BOB',
      'updatedBy': managerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createQrRequest({
    required String userUid,
    required String fullName,
    required String paymentOrderId,
    required double amount,
  }) async {
    if (userUid.isEmpty ||
        fullName.trim().length < 2 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(paymentOrderId) ||
        !amount.isFinite ||
        amount <= 0) {
      throw ArgumentError('Los datos de la solicitud de Member Card no son válidos.');
    }
    final requestRef =
        _firestore.collection('memberCardRequests').doc(paymentOrderId);
    final cardRef = _firestore.collection('wolves_member_card').doc(userUid);
    await _firestore.runTransaction((transaction) async {
      final card = await transaction.get(cardRef);
      final request = await transaction.get(requestRef);
      if (card.exists) {
        throw StateError('Tu cuenta ya tiene una Member Card emitida.');
      }
      if (request.exists) {
        final requestData = request.data();
        if (requestData?['userUid'] == userUid &&
            requestData?['status'] == 'awaiting_payment') {
          return;
        }
        throw StateError(
          'Ya existe una solicitud asociada a esta orden de pago.',
        );
      }
      transaction.set(requestRef, {
        'userUid': userUid,
        'fullName': fullName.trim(),
        'source': 'qr',
        'status': 'awaiting_payment',
        'amount': amount,
        'paymentOrderId': paymentOrderId,
        'deliveryDueAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reportQrPayment({
    required String requestId,
    required String userUid,
  }) async {
    final requestRef =
        _firestore.collection('memberCardRequests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      final data = request.data();
      if (!request.exists ||
          data?['userUid'] != userUid ||
          data?['source'] != 'qr') {
        throw StateError('No se encontró tu solicitud de pago.');
      }
      if (data?['status'] == 'payment_reported' ||
          data?['status'] == 'payment_confirmed') {
        return;
      }
      if (data?['status'] != 'awaiting_payment') {
        throw StateError('La solicitud ya no está esperando este pago.');
      }
      transaction.update(requestRef, {
        'status': 'payment_reported',
        'paymentReportedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markQrPaymentFailed({
    required String requestId,
    required String userUid,
  }) async {
    final requestRef =
        _firestore.collection('memberCardRequests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      final data = request.data();
      if (!request.exists ||
          data?['userUid'] != userUid ||
          data?['source'] != 'qr' ||
          data?['status'] != 'awaiting_payment') {
        throw StateError('No se encontró la solicitud de pago pendiente.');
      }
      transaction.update(requestRef, {
        'status': 'payment_failed',
        'paymentFailedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> confirmQrPayment({
    required String requestId,
    required String managerUid,
  }) async {
    final requestRef =
        _firestore.collection('memberCardRequests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final request = await transaction.get(requestRef);
      final data = request.data();
      if (!request.exists ||
          data?['source'] != 'qr' ||
          !const {'awaiting_payment', 'payment_reported'}
              .contains(data?['status'])) {
        throw StateError(
          'La solicitud no está disponible para confirmar el pago.',
        );
      }
      transaction.update(requestRef, {
        'status': 'payment_confirmed',
        'paymentVerifiedBy': managerUid,
        'paymentVerifiedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
