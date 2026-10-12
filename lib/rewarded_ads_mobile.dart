import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _androidTestAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
const _iosTestAdUnitId = 'ca-app-pub-3940256099942544/1712485313';

Future<void>? _initialization;

bool get isSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<void> initialize() {
  return _initialization ??= MobileAds.instance.initialize().then((_) {});
}

Future<bool> showRewarded({
  required String uid,
  required String customData,
  required String purpose,
}) async {
  if (!isSupported) {
    throw UnsupportedError(
      'Rewarded Ads solo está disponible en Android e iOS.',
    );
  }

  await initialize();
  final adUnitId = switch ((defaultTargetPlatform, purpose)) {
    (TargetPlatform.android, 'gameLives') => const String.fromEnvironment(
        'ADMOB_GAME_REWARDED_AD_UNIT_ID_ANDROID',
        defaultValue: _androidTestAdUnitId,
      ),
    (TargetPlatform.iOS, 'gameLives') => const String.fromEnvironment(
        'ADMOB_GAME_REWARDED_AD_UNIT_ID_IOS',
        defaultValue: _iosTestAdUnitId,
      ),
    (TargetPlatform.android, 'preferenceRound') => const String.fromEnvironment(
        'ADMOB_PREFERENCE_REWARDED_AD_UNIT_ID_ANDROID',
        defaultValue: _androidTestAdUnitId,
      ),
    (TargetPlatform.iOS, 'preferenceRound') => const String.fromEnvironment(
        'ADMOB_PREFERENCE_REWARDED_AD_UNIT_ID_IOS',
        defaultValue: _iosTestAdUnitId,
      ),
    _ => throw UnsupportedError(
        'El propósito o la plataforma del anuncio no está soportado.',
      ),
  };

  final loadedAd = Completer<RewardedAd>();
  await RewardedAd.load(
    adUnitId: adUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: loadedAd.complete,
      onAdFailedToLoad: (error) {
        loadedAd.completeError(
          StateError('No se pudo cargar el anuncio: $error'),
        );
      },
    ),
  );
  final ad = await loadedAd.future;
  await ad.setServerSideOptions(
    ServerSideVerificationOptions(userId: uid, customData: customData),
  );

  final rewardEarned = Completer<bool>();
  var earned = false;
  ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
    onAdDismissedFullScreenContent: (ad) {
      ad.dispose();
      if (!rewardEarned.isCompleted) rewardEarned.complete(earned);
    },
    onAdFailedToShowFullScreenContent: (ad, error) {
      ad.dispose();
      if (!rewardEarned.isCompleted) {
        rewardEarned.completeError(
          StateError('No se pudo mostrar el anuncio: $error'),
        );
      }
    },
  );

  try {
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
      },
    );
  } catch (_) {
    ad.dispose();
    rethrow;
  }
  return rewardEarned.future;
}
