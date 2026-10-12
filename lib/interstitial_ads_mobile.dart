import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _androidTestAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
const _iosTestAdUnitId = 'ca-app-pub-3940256099942544/4411468910';
const _minimumInterval = Duration(minutes: 3);
const _adTimeout = Duration(seconds: 8);

Future<void>? _initialization;
DateTime? _lastShownAt;
bool _showingAd = false;

bool get isSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<bool> showBeforeLeaving() async {
  if (!isSupported || _showingAd) return false;
  final now = DateTime.now();
  if (_lastShownAt != null &&
      now.difference(_lastShownAt!) < _minimumInterval) {
    return false;
  }

  final adUnitId = switch (defaultTargetPlatform) {
    TargetPlatform.android => const String.fromEnvironment(
        'ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID',
        defaultValue: _androidTestAdUnitId,
      ),
    TargetPlatform.iOS => const String.fromEnvironment(
        'ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS',
        defaultValue: _iosTestAdUnitId,
      ),
    _ => null,
  };
  if (adUnitId == null) return false;

  _showingAd = true;
  try {
    await (_initialization ??= MobileAds.instance.initialize().then((_) {}));
    final loadedAd = Completer<InterstitialAd>();
    var loadRequestExpired = false;
    await InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (loadRequestExpired || loadedAd.isCompleted) {
            ad.dispose();
          } else {
            loadedAd.complete(ad);
          }
        },
        onAdFailedToLoad: (error) {
          if (!loadRequestExpired && !loadedAd.isCompleted) {
            loadedAd.completeError(
              StateError('No se pudo cargar el interstitial: $error'),
            );
          }
        },
      ),
    );
    final InterstitialAd ad;
    try {
      ad = await loadedAd.future.timeout(_adTimeout);
    } catch (_) {
      loadRequestExpired = true;
      rethrow;
    }
    final finished = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) => _lastShownAt = DateTime.now(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!finished.isCompleted) finished.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!finished.isCompleted) finished.complete(false);
      },
    );
    try {
      await ad.show();
      return await finished.future.timeout(_adTimeout, onTimeout: () => false);
    } catch (_) {
      ad.dispose();
      rethrow;
    }
  } catch (error, stackTrace) {
    debugPrint('Interstitial no disponible; continúa la navegación: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  } finally {
    _showingAd = false;
  }
}
