// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class BackgroundMusic {
  html.AudioElement? _audio;
  html.AudioElement? _howl;
  html.AudioElement? _orderBell;
  html.AudioElement? _orderAnnouncement;
  html.AudioElement? _successTone;
  Timer? _orderAlarmTimer;
  bool _orderAlarmActive = false;
  int _orderAlarmGeneration = 0;

  bool get isSupported => true;

  Future<void> play() async {
    final audio = _audio ??= html.AudioElement()
      ..src =
          Uri.base.resolve('assets/assets/audio/cancion_oficial.mp3').toString()
      ..loop = true
      ..volume = 0.16
      ..preload = 'auto';
    await audio.play();
  }

  Future<Duration> playHowl() async {
    final howl = _howl ??= html.AudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/aullido.mp3').toString()
      ..loop = false
      ..volume = 0.72
      ..preload = 'auto';

    howl.currentTime = 0;
    try {
      await howl.play().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      howl.pause();
      howl.currentTime = 0;
      throw TimeoutException(
        'El navegador tardó demasiado en iniciar el aullido.',
        const Duration(seconds: 2),
      );
    }

    final seconds = howl.duration;
    if (!seconds.isFinite || seconds <= 0) {
      throw StateError('El archivo de aullido no tiene una duración válida.');
    }
    final duration = Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
    return duration;
  }

  Future<void> playOrderBell() async {
    final orderBell = _orderBell ??= html.AudioElement()
      ..src = Uri.base
          .resolve('assets/assets/audio/kitchen_order_tone.mp3')
          .toString()
      ..loop = false
      ..volume = 0.8
      ..preload = 'auto';
    final announcement = _orderAnnouncement ??= html.AudioElement()
      ..src = Uri.base
          .resolve('assets/assets/audio/kitchen_order_announcement.wav')
          .toString()
      ..loop = false
      ..volume = 1
      ..preload = 'auto';
    orderBell.currentTime = 0;
    announcement.currentTime = 0;
    await Future.wait([orderBell.play(), announcement.play()]);
  }

  Future<void> playRedemptionSuccess() async {
    try {
      if (js_util.hasProperty(html.window.navigator, 'vibrate')) {
        final vibrated = js_util.callMethod<bool>(
          html.window.navigator,
          'vibrate',
          [
            <int>[120, 60, 120],
          ],
        );
        if (!vibrated) {
          debugPrint('El navegador no permitió vibrar al confirmar el canje.');
        }
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo activar la vibración del canje: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    final successTone = _successTone ??= html.AudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/order_bell.wav').toString()
      ..loop = false
      ..volume = 0.48
      ..playbackRate = 1.6
      ..preload = 'auto';
    successTone.currentTime = 0;
    await successTone.play();
  }

  Future<void> startOrderAlarm() async {
    if (_orderAlarmActive) return;
    _orderAlarmActive = true;
    final generation = ++_orderAlarmGeneration;
    final orderBell = _orderBell ??= html.AudioElement()
      ..src = Uri.base
          .resolve('assets/assets/audio/kitchen_order_tone.mp3')
          .toString()
      ..volume = 0.8
      ..preload = 'auto';
    final announcement = _orderAnnouncement ??= html.AudioElement()
      ..src = Uri.base
          .resolve('assets/assets/audio/kitchen_order_announcement.wav')
          .toString()
      ..loop = false
      ..volume = 1
      ..preload = 'auto';
    orderBell.loop = true;
    orderBell.currentTime = 0;
    try {
      await orderBell.play();
      if (!_orderAlarmActive || generation != _orderAlarmGeneration) return;
      announcement.currentTime = 0;
      await announcement.play();
      if (!_orderAlarmActive || generation != _orderAlarmGeneration) return;
      _orderAlarmTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(_repeatOrderAnnouncement(generation));
      });
    } catch (_) {
      await stopOrderAlarm();
      rethrow;
    }
  }

  Future<void> stopOrderAlarm() async {
    _orderAlarmActive = false;
    _orderAlarmTimer?.cancel();
    _orderAlarmTimer = null;
    _orderAlarmGeneration++;
    final orderBell = _orderBell;
    orderBell?.pause();
    if (orderBell != null) {
      orderBell.currentTime = 0;
      orderBell.loop = false;
    }
    final announcement = _orderAnnouncement;
    announcement?.pause();
    if (announcement != null) announcement.currentTime = 0;
  }

  Future<void> _repeatOrderAnnouncement(int generation) async {
    if (!_orderAlarmActive || generation != _orderAlarmGeneration) return;
    final announcement = _orderAnnouncement;
    if (announcement == null) {
      throw StateError('No se preparó la voz de la alarma de cocina.');
    }
    try {
      announcement.currentTime = 0;
      await announcement.play();
    } catch (error, stackTrace) {
      debugPrint('No se pudo repetir la voz de la alarma de cocina: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> stop() async {
    final audio = _audio;
    if (audio == null) return;
    audio.pause();
    audio.currentTime = 0;
  }

  Future<void> dispose() async {
    await stop();
    _howl?.pause();
    _howl?.currentTime = 0;
    await stopOrderAlarm();
    _successTone?.pause();
    _successTone?.currentTime = 0;
    _orderBell = null;
    _orderAnnouncement = null;
    _successTone = null;
    _howl = null;
    _audio = null;
  }
}
