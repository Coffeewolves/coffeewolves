import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/member_card_print_service.dart';

void main() {
  test('PVC print layout uses the required 85.5 x 54 mm dimensions', () {
    expect(MemberCardPrintService.widthMm, 85.5);
    expect(MemberCardPrintService.heightMm, 54);
  });
}
