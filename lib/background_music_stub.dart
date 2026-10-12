import 'package:flutter/services.dart';

class BackgroundMusic {
  bool get isSupported => false;

  Future<void> play() async {}

  Future<Duration> playHowl() async => const Duration(seconds: 5);

  Future<void> playOrderBell() => SystemSound.play(SystemSoundType.alert);

  Future<void> playRedemptionSuccess() async {
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.vibrate();
  }

  Future<void> startOrderAlarm() => SystemSound.play(SystemSoundType.alert);

  Future<void> stopOrderAlarm() async {}

  Future<void> stop() async {}

  Future<void> dispose() async {}
}
