import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/payment_api_service.dart';

void main() {
  group('PaymentOrder', () {
    test('parses a pending order with an HTTPS QR image URL', () {
      final order = PaymentOrder.fromJson({
        'orderId': 'order-123',
        'amount': 180,
        'qrImageUrl': 'https://payments.example/qr/order-123.png',
        'status': 'pending',
      });

      expect(order.id, 'order-123');
      expect(order.amount, 180);
      expect(order.qrImageUrl.scheme, 'https');
      expect(order.status, 'pending');
    });

    test('normalizes backend status exitoso to paid', () {
      final order = PaymentOrder.fromJson({
        'orderId': 'order-123',
        'amount': 180,
        'qrImageUrl': 'https://payments.example/qr/order-123.png',
        'status': 'exitoso',
      });

      expect(order.status, 'paid');
    });

    test('rejects malformed orders and insecure QR URLs', () {
      expect(
        () => PaymentOrder.fromJson({
          'orderId': 'order-123',
          'amount': 180,
          'qrImageUrl': 'http://payments.example/qr.png',
          'status': 'pending',
        }),
        throwsFormatException,
      );
      expect(
        () => PaymentOrder.fromJson({
          'orderId': 'order-123',
          'amount': 0,
          'qrImageUrl': 'https://payments.example/qr.png',
          'status': 'paid',
        }),
        throwsFormatException,
      );
      expect(
        () => PaymentOrder.fromJson({
          'orderId': 'order-123',
          'amount': 180,
          'qrImageUrl': 'https://payments.example/qr.png',
          'status': 'settled',
        }),
        throwsFormatException,
      );
    });
  });
}
