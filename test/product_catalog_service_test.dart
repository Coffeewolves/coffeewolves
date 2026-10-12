import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/product_catalog_service.dart';

void main() {
  group('Product stock by size', () {
    test('parses persisted size stock and preserves the aggregate', () {
      final product = Product.fromData('hoodie-wolves', {
        'name': 'Hoodie Wolves Club',
        'category': 'moda_alfa',
        'family': wolvesShopRootFamily,
        'stock': 21,
        'stockBySize': {
          'S': 3,
          'M': 5,
          'L': 4,
          'XL': 2,
          '2XL': 4,
          '3XL': 3,
        },
        'price': 320,
        'isVisible': true,
      });

      expect(product.hasSizes, isTrue);
      expect(product.stockBySize['M'], 5);
      expect(product.stockBySize['2XL'], 4);
      expect(product.stockBySize['3XL'], 3);
      expect(product.stock, 21);
    });

    test('rejects negative or inconsistent size stock', () {
      expect(
        () => Product.fromData('hoodie-wolves', {
          'name': 'Hoodie Wolves Club',
          'category': 'moda_alfa',
          'family': wolvesShopRootFamily,
          'stock': 14,
          'stockBySize': {'S': 3, 'M': 5, 'L': 4, 'XL': 1},
          'price': 320,
          'isVisible': true,
        }),
        throwsFormatException,
      );
      expect(
        () => Product.fromData('hoodie-wolves', {
          'name': 'Hoodie Wolves Club',
          'category': 'moda_alfa',
          'family': wolvesShopRootFamily,
          'stock': 14,
          'stockBySize': {'S': 3, 'M': 5, 'L': 4, 'XL': 1, '4XL': 1},
          'price': 320,
          'isVisible': true,
        }),
        throwsFormatException,
      );
      expect(
        () => Product.fromData('hoodie-wolves', {
          'name': 'Hoodie Wolves Club',
          'category': 'moda_alfa',
          'family': wolvesShopRootFamily,
          'stock': 14,
          'stockBySize': {'S': 3, 'M': 5, 'L': 4, 'XL': -1},
          'price': 320,
          'isVisible': true,
        }),
        throwsFormatException,
      );
    });

    test('continues to parse existing products without sizes', () {
      final product = Product.fromData('gorra-alfa', {
        'name': 'Gorra Alfa',
        'category': 'moda_alfa',
        'stock': 8,
        'price': 140,
        'isVisible': true,
      });

      expect(product.hasSizes, isFalse);
      expect(product.stockBySize, isEmpty);
      expect(product.stock, 8);
    });

    test('reads an optional image URL for the shop and POS', () {
      final product = Product.fromData('gorra-alfa', {
        'name': 'Gorra Alfa',
        'category': 'moda_alfa',
        'stock': 8,
        'price': 140,
        'isVisible': true,
        'imageUrl': 'https://storage.example.com/gorra.jpg',
      });

      expect(product.imageUrl, 'https://storage.example.com/gorra.jpg');
    });

    test('reads the optional internal product code', () {
      final product = Product.fromData('gorra-alfa', {
        'name': 'Gorra Alfa',
        'category': 'moda_alfa',
        'stock': 8,
        'price': 140,
        'isVisible': true,
        'sku': 'GOR-ALFA-01',
      });

      expect(product.sku, 'GOR-ALFA-01');
    });

    test('defaults the product code and rejects non-string codes', () {
      final legacyProduct = Product.fromData('gorra-alfa', {
        'name': 'Gorra Alfa',
        'category': 'moda_alfa',
        'stock': 8,
        'price': 140,
        'isVisible': true,
      });
      expect(legacyProduct.sku, isEmpty);
      expect(
        () => Product.fromData('gorra-alfa', {
          'name': 'Gorra Alfa',
          'category': 'moda_alfa',
          'stock': 8,
          'price': 140,
          'isVisible': true,
          'sku': 123,
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-string product image URL', () {
      expect(
        () => Product.fromData('gorra-alfa', {
          'name': 'Gorra Alfa',
          'category': 'moda_alfa',
          'stock': 8,
          'price': 140,
          'isVisible': true,
          'imageUrl': 123,
        }),
        throwsFormatException,
      );
    });
  });
}
