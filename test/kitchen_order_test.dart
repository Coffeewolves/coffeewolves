import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/kitchen_order.dart';

void main() {
  group('KitchenOrder data model', () {
    test('serializes only operational fields for kitchen display', () {
      final order = KitchenOrder(
        id: 'order-123',
        tableNumber: 4,
        serviceType: KitchenServiceType.dineIn,
        createdAt: DateTime.utc(2026, 10, 14, 20),
        status: KitchenOrderStatus.pending,
        items: const [
          KitchenOrderItem(
            quantity: 2,
            name: 'Latte',
            size: 'Grande',
            modifications: ['Leche de avena', 'Sin azúcar'],
          ),
        ],
      );

      final data = order.toMap();
      final item = (data['items'] as List<Map<String, dynamic>>).single;

      expect(data.keys, containsAll([
        'orderId',
        'tableNumber',
        'serviceType',
        'createdAt',
        'items',
        'status',
      ]));
      expect(data.keys, isNot(contains('total')));
      expect(data.keys, isNot(contains('paymentMethod')));
      expect(item, {
        'quantity': 2,
        'name': 'Latte',
        'size': 'Grande',
        'modifications': ['Leche de avena', 'Sin azúcar'],
      });
    });
  });
}
