// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class BackgroundMusic {
  html.AudioElement? _audio;
  html.AudioElement? _howl;
  html.AudioElement? _orderBell;
  html.AudioElement? _successTone;
  Timer? _orderAlarmTimer;
  bool _orderAlarmActive = false;
  bool _usingSpeechAlarm = false;
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
    if (_orderAlarmActive) return;
    if (js_util.hasProperty(html.window, 'speechSynthesis')) {
      final speechSynthesis =
          js_util.getProperty<Object?>(html.window, 'speechSynthesis');
      if (speechSynthesis != null) {
        _orderAlarmActive = true;
        _usingSpeechAlarm = true;
        final generation = ++_orderAlarmGeneration;
        _speakOrderAnnouncement(speechSynthesis, generation);
        return;
      }
    }

    _orderAlarmActive = true;
    final orderBell = _orderBell ??= html.AudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/order_bell.wav').toString()
      ..volume = 0.8
      ..preload = 'auto';
    orderBell.loop = true;
    orderBell.currentTime = 0;
    await orderBell.play();
  }

  Future<void> stopOrderAlarm() async {
    _orderAlarmActive = false;
    _orderAlarmTimer?.cancel();
    _orderAlarmTimer = null;
    _orderAlarmGeneration++;
    if (_usingSpeechAlarm) {
      final speechSynthesis =
          js_util.getProperty<Object?>(html.window, 'speechSynthesis');
      if (speechSynthesis != null) {
        js_util.callMethod<void>(speechSynthesis, 'cancel', const []);
      }
      _usingSpeechAlarm = false;
    }
    final orderBell = _orderBell;
    if (orderBell == null) return;
    orderBell.pause();
    orderBell.currentTime = 0;
    orderBell.loop = false;
  }

  void _speakOrderAnnouncement(Object speechSynthesis, int generation) {
    if (!_orderAlarmActive || generation != _orderAlarmGeneration) return;

    final constructor =
        js_util.getProperty<Object?>(html.window, 'SpeechSynthesisUtterance');
    if (constructor == null) {
      throw StateError('El navegador no permite anunciar pedidos por voz.');
    }
    final utterance = js_util.callConstructor<Object>(
      constructor,
      ['Tienes un nuevo pedido'],
    );
    js_util.setProperty(utterance, 'lang', 'es-MX');
    js_util.setProperty(utterance, 'rate', 0.95);
    js_util.setProperty(utterance, 'pitch', 1.1);

    final voices = js_util.callMethod<Object?>(
      speechSynthesis,
      'getVoices',
      const [],
    );
    if (voices != null) {
      final voice = _preferredSpanishVoice(voices);
      if (voice != null) js_util.setProperty(utterance, 'voice', voice);
    }

    js_util.callMethod<void>(speechSynthesis, 'speak', [utterance]);
    _orderAlarmTimer = Timer(const Duration(seconds: 3), () {
      _repeatOrderAnnouncement(speechSynthesis, generation);
    });
  }

  void _repeatOrderAnnouncement(Object speechSynthesis, int generation) {
    if (!_orderAlarmActive || generation != _orderAlarmGeneration) return;
    if (js_util.getProperty<bool>(speechSynthesis, 'speaking')) {
      _orderAlarmTimer = Timer(const Duration(seconds: 1), () {
        _repeatOrderAnnouncement(speechSynthesis, generation);
      });
      return;
    }
    _speakOrderAnnouncement(speechSynthesis, generation);
  }

  Object? _preferredSpanishVoice(Object voices) {
    const feminineVoiceNames = [
      'sabina',
      'paulina',
      'monica',
      'mónica',
      'dalia',
      'elena',
      'laura',
      'lucia',
      'lucía',
      'helena',
      'sofia',
      'sofía',
      'carmen',
      'andrea',
      'valentina',
      'marisol',
      'female',
      'mujer',
    ];
    final length = js_util.getProperty<int>(voices, 'length');
    Object? preferredVoice;
    var preferredScore = -1;
    for (var index = 0; index < length; index++) {
      final voice = js_util.getProperty<Object?>(voices, index);
      if (voice == null) continue;
      final language =
          (js_util.getProperty<Object?>(voice, 'lang')?.toString() ?? '')
              .toLowerCase();
      if (!language.startsWith('es')) continue;
      final name =
          (js_util.getProperty<Object?>(voice, 'name')?.toString() ?? '')
              .toLowerCase();
      var score = language == 'es-mx' ? 2 : 0;
      if (feminineVoiceNames.any(name.contains)) score += 10;
      if (score > preferredScore) {
        preferredScore = score;
        preferredVoice = voice;
      }
    }
    return preferredVoice;
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
