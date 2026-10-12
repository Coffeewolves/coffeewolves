import 'rewarded_ads_stub.dart'
    if (dart.library.io) 'rewarded_ads_mobile.dart' as platform;

enum RewardedAdPurpose { gameLives, preferenceRound }

class RewardedAdsService {
  const RewardedAdsService._();

  static bool get isSupported => platform.isSupported;

  static Future<void> initialize() => platform.initialize();

  static Future<bool> showRewarded({
    required String uid,
    required String customData,
    required RewardedAdPurpose purpose,
  }) =>
      platform.showRewarded(
        uid: uid,
        customData: customData,
        purpose: purpose.name,
      );
}
