import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/reward_audit_service.dart';

void main() {
  test('Cold Brew album has 16 distinct figures in menu order', () {
    expect(coldBrewFigures, hasLength(16));
    expect(
      coldBrewFigures.map((figure) => figure.id).toSet(),
      hasLength(16),
    );
    expect(coldBrewFigures.first.name, 'Cold Brew');
    expect(coldBrewFigures.last.name, 'Lulo Milk Cold Brew');
  });
}
