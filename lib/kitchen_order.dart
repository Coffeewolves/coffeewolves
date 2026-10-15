import 'package:cloud_firestore/cloud_firestore.dart';

enum KitchenOrderStatus { pending, preparing, ready }

enum KitchenServiceType { dineIn, takeaway, delivery }

class KitchenOrderItem {
  const KitchenOrderItem({
    required this.quantity,
    required this.name,
    this.size,
    this.modifications = const [],
  });

  final int quantity;
  final String name;
  final String? size;
  final List<String> modifications;

  factory KitchenOrderItem.fromMap(Map<String, dynamic> data) {
    return KitchenOrderItem(
      quantity: data['quantity'] as int? ?? 0,
      name: data['name'] as String? ?? 'Producto',
      size: data['size'] as String?,
      modifications: (data['modifications'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() => {
        'quantity': quantity,
        'name': name,
        if (size != null && size!.isNotEmpty) 'size': size,
        'modifications': modifications,
      };
}

class KitchenOrder {
  const KitchenOrder({
    required this.id,
    required this.serviceType,
    required this.createdAt,
    required this.items,
    required this.status,
    this.tableNumber,
    this.customerName,
  });

  final String id;
  final int? tableNumber;
  final String? customerName;
  final KitchenServiceType serviceType;
  final DateTime createdAt;
  final List<KitchenOrderItem> items;
  final KitchenOrderStatus status;

  KitchenOrder withItems(List<KitchenOrderItem> kitchenItems) => KitchenOrder(
        id: id,
        tableNumber: tableNumber,
        customerName: customerName,
        serviceType: serviceType,
        createdAt: createdAt,
        items: kitchenItems,
        status: status,
      );

  factory KitchenOrder.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : rawCreatedAt is DateTime
            ? rawCreatedAt
            : DateTime.fromMillisecondsSinceEpoch(0);
    final rawItems = data['items'] as List<dynamic>? ?? const [];
    final status = switch (data['status']) {
      'preparing' => KitchenOrderStatus.preparing,
      'ready' => KitchenOrderStatus.ready,
      _ => KitchenOrderStatus.pending,
    };
    final serviceType = switch (data['serviceType']) {
      'dineIn' => KitchenServiceType.dineIn,
      'delivery' => KitchenServiceType.delivery,
      _ => KitchenServiceType.takeaway,
    };

    return KitchenOrder(
      id: snapshot.id,
      tableNumber: data['tableNumber'] as int?,
      customerName: data['customerName'] as String?,
      serviceType: serviceType,
      createdAt: createdAt,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(KitchenOrderItem.fromMap)
          .toList(growable: false),
      status: status,
    );
  }

  Map<String, dynamic> toMap() => {
        'orderId': id,
        if (tableNumber != null) 'tableNumber': tableNumber,
        if (customerName != null && customerName!.isNotEmpty)
          'customerName': customerName,
        'serviceType': switch (serviceType) {
          KitchenServiceType.dineIn => 'dineIn',
          KitchenServiceType.takeaway => 'takeaway',
          KitchenServiceType.delivery => 'delivery',
        },
        'createdAt': Timestamp.fromDate(createdAt),
        'items': items.map((item) => item.toMap()).toList(growable: false),
        'status': switch (status) {
          KitchenOrderStatus.pending => 'pending',
          KitchenOrderStatus.preparing => 'preparing',
          KitchenOrderStatus.ready => 'ready',
        },
      };
}
