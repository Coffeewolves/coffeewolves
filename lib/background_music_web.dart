// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class BackgroundMusic {
  html.AudioElement? _audio;
  html.AudioElement? _howl;
  html.AudioElement? _orderBell;
  html.AudioElement? _successTone;

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

    if (howl.readyState < 1) {
      howl.load();
      await Future.any([
        howl.onLoadedMetadata.first,
        howl.onError.first.then<void>((_) {
          throw StateError('No se pudieron leer los metadatos del aullido.');
        }),
      ]).timeout(const Duration(seconds: 10));
    }

    final seconds = howl.duration;
    if (!seconds.isFinite || seconds <= 0) {
      throw StateError('El archivo de aullido no tiene una duración válida.');
    }
    final duration = Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
    howl.currentTime = 0;
    await howl.play();
    return duration;
  }

  Future<void> playOrderBell() async {
    final orderBell = _orderBell ??= html.AudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/order_bell.wav').toString()
      ..loop = false
      ..volume = 0.8
      ..preload = 'auto';
    orderBell.currentTime = 0;
    await orderBell.play();
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
    final orderBell = _orderBell ??= html.AudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/order_bell.wav').toString()
      ..volume = 0.8
      ..preload = 'auto';
    orderBell.loop = true;
    orderBell.currentTime = 0;
    await orderBell.play();
  }

  Future<void> stopOrderAlarm() async {
    final orderBell = _orderBell;
    if (orderBell == null) return;
    orderBell.pause();
    orderBell.currentTime = 0;
    orderBell.loop = false;
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
    _successTone = null;
    _howl = null;
    _audio = null;
  }
}
