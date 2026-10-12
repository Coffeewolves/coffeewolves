import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/business_operations_service.dart';

void main() {
  group('Customer support automated messages', () {
    test('returns a specific acknowledgement for each feedback type', () {
      expect(
        customerComplaintAutoReply('suggestion'),
        contains('Gerencia la recibió'),
      );
      expect(
        customerComplaintAutoReply('compliment'),
        contains('Nos alegra'),
      );
      expect(
        customerComplaintAutoReply('complaint'),
        contains('podrás consultar aquí su estado'),
      );
    });

    test('rejects unknown feedback types', () {
      expect(
        () => customerComplaintAutoReply('unknown'),
        throwsArgumentError,
      );
    });

    test('returns a customer-facing message for each case status', () {
      expect(
        customerComplaintStatusMessage('new'),
        contains('pendiente de revisión'),
      );
      expect(
        customerComplaintStatusMessage('reviewing'),
        contains('está revisando'),
      );
      expect(
        customerComplaintStatusMessage('resolved'),
        contains('marcó tu caso como resuelto'),
      );
      expect(
        () => customerComplaintStatusMessage('unknown'),
        throwsArgumentError,
      );
    });
  });
}
