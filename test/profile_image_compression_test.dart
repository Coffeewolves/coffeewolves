import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wolves_club/profile_creation_form.dart';

void main() {
  test('compresses profile images below 200 KiB as JPEG', () {
    final source = img.Image(width: 1200, height: 900);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          x % 256,
          y % 256,
          (x + y) % 256,
        );
      }
    }
    final sourceBytes = Uint8List.fromList(img.encodePng(source));

    final compressed = compressProfileImageBytes(sourceBytes);

    expect(compressed.length, lessThanOrEqualTo(200 * 1024));
    expect(compressed[0], 0xff);
    expect(compressed[1], 0xd8);
    final decoded = img.decodeJpg(compressed);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(512));
    expect(decoded.height, lessThanOrEqualTo(512));
  });

  test('rejects bytes that are not a decodable image', () {
    expect(
      () => compressProfileImageBytes(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
