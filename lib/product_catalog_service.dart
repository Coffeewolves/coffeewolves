import 'package:cloud_firestore/cloud_firestore.dart';

const wolvesShopRootFamily = 'Merch Wolves Shop';
const wolvesShopSizes = ['S', 'M', 'L', 'XL', '2XL', '3XL'];
const wolvesShopProductCategories = [
  'merch',
  'merchandising',
  'merch_wolves_shop',
  'wolves_shop',
  'moda_alfa',
  'accesorios',
  'estilo_de_vida',
  'taza',
  'tazas',
  'tazas_coleccionables',
  'coleccionables',
  'collectibles',
];
const foodAndBeverageCategories = [
  'food',
  'beverage',
  'beverages',
  'smoothies',
  'combos_pack',
  'comida',
  'bebida',
  'pet_friendly',
];

bool isWolvesShopProduct(Product product) {
  return product.family == wolvesShopRootFamily ||
      wolvesShopProductCategories.contains(product.category);
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.family,
    required this.stock,
    required this.price,
    required this.isVisible,
    this.description = '',
    this.stockBySize = const {},
    this.imageUrl,
    this.sku = '',
  });

  final String id;
  final String name;
  final String category;
  final String family;
  final int stock;
  final double price;
  final bool isVisible;
  final String description;
  final Map<String, int> stockBySize;
  final String? imageUrl;
  final String sku;

  bool get hasSizes => stockBySize.isNotEmpty;

  factory Product.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) =>
      Product.fromData(document.id, document.data());

  factory Product.fromData(String id, Map<String, dynamic> data) {
    final name = data['name'];
    final category = data['category'];
    final family = data['family'];
    final stock = data['stock'];
    final price = data['price'];
    final isVisible = data['isVisible'];
    final description = data['description'];
    final imageUrl = data['imageUrl'];
    final sku = data['sku'];
    final rawStockBySize = data['stockBySize'];
    final stockBySize = <String, int>{};
    if (rawStockBySize != null) {
      if (rawStockBySize is! Map) {
        throw FormatException(
          'El stock por talle del producto $id no es válido.',
        );
      }
      for (final entry in rawStockBySize.entries) {
        if (entry.key is! String ||
            !wolvesShopSizes.contains(entry.key) ||
            entry.value is! int ||
            (entry.value as int) < 0) {
          throw FormatException(
            'El stock por talle del producto $id no es válido.',
          );
        }
        stockBySize[entry.key as String] = entry.value as int;
      }
      final totalBySize =
          stockBySize.values.fold<int>(0, (total, units) => total + units);
      if (stock is! int || totalBySize != stock) {
        throw FormatException(
          'El stock total y el stock por talle del producto $id no coinciden.',
        );
      }
    }
    if (name is! String ||
        category is! String ||
        (family != null && family is! String) ||
        stock is! int ||
        price is! num ||
        isVisible is! bool ||
        (description != null && description is! String) ||
        (imageUrl != null && imageUrl is! String) ||
        (sku != null && sku is! String)) {
      throw FormatException(
        'El producto $id no cumple el esquema requerido.',
      );
    }
    return Product(
      id: id,
      name: name,
      category: category,
      family: family as String? ?? '',
      stock: stock,
      price: price.toDouble(),
      isVisible: isVisible,
      description: description as String? ?? '',
      stockBySize: Map.unmodifiable(stockBySize),
      imageUrl: imageUrl as String?,
      sku: sku as String? ?? '',
    );
  }
}

class ProductCatalogService {
  ProductCatalogService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<Product>> getFoodAndBeverageMenu() {
    return _firestore
        .collection('products')
        .where('isVisible', isEqualTo: true)
        .snapshots()
        .map((snapshot) => _productsMatching(
              snapshot,
              includeHidden: false,
              predicate: (data) =>
                  foodAndBeverageCategories.contains(data['category']) &&
                  data['family'] != wolvesShopRootFamily &&
                  data['family'] != 'Wolves Shop' &&
                  !wolvesShopProductCategories.contains(data['category']),
            ));
  }

  Stream<List<Product>> getWolvesShopItems({bool includeHidden = false}) {
    final products = _firestore.collection('products');
    final query =
        includeHidden ? products : products.where('isVisible', isEqualTo: true);
    return query.snapshots().map(
          (snapshot) => _productsMatching(
            snapshot,
            includeHidden: includeHidden,
            predicate: (data) =>
                data['family'] == wolvesShopRootFamily ||
                wolvesShopProductCategories.contains(data['category']),
          ),
        );
  }

  Stream<List<Product>> getAdminWolvesShopItems() {
    return getWolvesShopItems(includeHidden: true);
  }

  Stream<List<Product>> getCoffeeMethods() {
    return _firestore
        .collection('products')
        .where('isVisible', isEqualTo: true)
        .snapshots()
        .map((snapshot) => _productsMatching(
              snapshot,
              includeHidden: false,
              predicate: (data) =>
                  data['category'] == 'metodos' &&
                  data['family'] != wolvesShopRootFamily &&
                  data['family'] != 'Wolves Shop' &&
                  !wolvesShopProductCategories.contains(data['category']),
            ));
  }

  List<Product> _productsMatching(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required bool includeHidden,
    required bool Function(Map<String, dynamic>) predicate,
  }) {
    return snapshot.docs
        .where((document) => predicate(document.data()))
        .map(Product.fromFirestore)
        .where((product) => includeHidden || product.isVisible)
        .toList(growable: false);
  }
}
