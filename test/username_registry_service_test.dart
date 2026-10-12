import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/username_registry_service.dart';

void main() {
  group('UsernameRegistryService', () {
    test('normalizes Username case and surrounding spaces', () {
      expect(
          UsernameRegistryService.normalize('  CoffeeWolf_7 '), 'coffeewolf_7');
    });

    test('accepts valid Username characters and length', () {
      expect(UsernameRegistryService.validate('Wolf.Cafe-7'), isNull);
    });

    test('rejects spaces, unsupported characters, and invalid lengths', () {
      expect(UsernameRegistryService.validate('Coffee Wolf'), isNotNull);
      expect(UsernameRegistryService.validate('éclair'), isNotNull);
      expect(UsernameRegistryService.validate('ab'), isNotNull);
      expect(UsernameRegistryService.validate('a' * 21), isNotNull);
    });
  });
}
