import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/mischief_wall_service.dart';

void main() {
  group('mischiefPostLifetime', () {
    test('always uses seven days regardless of community growth', () {
      expect(mischiefPostLifetime(), const Duration(days: 7));
    });
  });

  group('videoContentTypeForFileName', () {
    test('detects supported video extensions case-insensitively', () {
      expect(
        MischiefWallService.videoContentTypeForFileName('Perrito.MOV'),
        'video/quicktime',
      );
      expect(
        MischiefWallService.videoContentTypeForFileName('travesura.webm'),
        'video/webm',
      );
    });

    test('rejects formats not supported in the wall', () {
      expect(
        () => MischiefWallService.videoContentTypeForFileName('video.avi'),
        throwsFormatException,
      );
    });
  });
}
