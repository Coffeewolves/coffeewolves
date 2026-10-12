import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/user_roles.dart';

void main() {
  group('normalizeUserRole', () {
    test('maps gerente to the protected admin role', () {
      expect(normalizeUserRole('gerente'), 'admin');
      expect(normalizeUserRole(' GERENTE '), 'admin');
      expect(normalizeUserRole('gerencia'), 'admin');
      expect(normalizeUserRole('Gerencia'), 'admin');
      expect(normalizeUserRole('manager'), 'admin');
      expect(normalizeUserRole('management'), 'admin');
    });

    test('preserves authorized staff roles and normalizes clientes', () {
      expect(normalizeUserRole('barista'), 'barista');
      expect(normalizeUserRole('cajero'), 'cajero');
      expect(normalizeUserRole('cliente'), 'user');
    });

    test('treats unknown or non-string roles as regular users', () {
      expect(normalizeUserRole('owner'), 'user');
      expect(normalizeUserRole(null), 'user');
    });
  });

}
