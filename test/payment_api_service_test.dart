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

  group('PaymentOrderStatus', () {
    test('validates the backend order ID, amount, and paid status', () {
      final payment = PaymentOrderStatus.fromJson(
        {
          'orderId': 'order-123',
          'amount': 180,
          'status': 'exitoso',
        },
        expectedOrderId: 'order-123',
      );

      expect(payment.id, 'order-123');
      expect(payment.amount, 180);
      expect(payment.status, 'paid');
    });

    test('rejects a missing amount or an unrelated order ID', () {
      expect(
        () => PaymentOrderStatus.fromJson(
          {
            'orderId': 'order-123',
            'status': 'paid',
          },
          expectedOrderId: 'order-123',
        ),
        throwsFormatException,
      );
      expect(
        () => PaymentOrderStatus.fromJson(
          {
            'orderId': 'other-order',
            'amount': 180,
            'status': 'paid',
          },
          expectedOrderId: 'order-123',
        ),
        throwsFormatException,
      );
    });
  });
}
