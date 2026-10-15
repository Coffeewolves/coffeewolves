import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/cold_brew_qr_payload.dart';

void main() {
  group('Member Card QR payloads', () {
    test('keeps a raw card number', () {
      expect(memberCardValueFromQr('CW-000123'), 'CW-000123');
    });

    test('extracts a card number from a URL', () {
      expect(
        memberCardValueFromQr(
          'https://coffeewolves.example/member?memberCard=CW-000123',
        ),
        'CW-000123',
      );
    });
  });

  group('Cold Brew figure QR payloads', () {
    test('builds and reads a valid figure payload', () {
      final payload = coldBrewFigureQrPayload('orange');

      expect(payload, 'coffee-wolves:cold-brew-figure:orange');
      expect(parseColdBrewFigureQr(payload), 'orange');
    });

    test('accepts a known figure id directly', () {
      expect(parseColdBrewFigureQr('classic'), 'classic');
    });

    test('accepts a figure id from a URL', () {
      expect(
        parseColdBrewFigureQr(
          'https://coffeewolves.example/figure?figureId=orange',
        ),
        'orange',
      );
    });

    test('rejects unknown figure codes', () {
      expect(
        () => parseColdBrewFigureQr('coffee-wolves:cold-brew-figure:unknown'),
        throwsFormatException,
      );
    });
  });
}
