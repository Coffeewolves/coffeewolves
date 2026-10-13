import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/mischief_wall_service.dart';

void main() {
  group('mischiefPostLifetime', () {
    test('uses seven days for a small community', () {
      expect(
        mischiefPostLifetime(memberCount: 4999, postsToday: 999),
        const Duration(days: 7),
      );
    });

    test('uses three days starting at five thousand members', () {
      expect(
        mischiefPostLifetime(memberCount: 5000, postsToday: 999),
        const Duration(days: 3),
      );
    });

    test('uses one day when publication volume reaches one thousand', () {
      expect(
        mischiefPostLifetime(memberCount: 5000, postsToday: 1000),
        const Duration(days: 1),
      );
    });

    test('volume limit takes precedence over community size', () {
      expect(
        mischiefPostLifetime(memberCount: 100, postsToday: 1000),
        const Duration(days: 1),
      );
    });
  });
}
