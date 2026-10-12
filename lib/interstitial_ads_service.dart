import 'interstitial_ads_stub.dart'
    if (dart.library.io) 'interstitial_ads_mobile.dart' as platform;

class InterstitialAdsService {
  const InterstitialAdsService._();

  static bool get isSupported => platform.isSupported;

  static Future<bool> showBeforeLeaving() => platform.showBeforeLeaving();
}
