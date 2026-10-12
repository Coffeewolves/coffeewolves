bool get isSupported => false;

Future<void> initialize() async {}

Future<bool> showRewarded({
  required String uid,
  required String customData,
  required String purpose,
}) {
  throw UnsupportedError('Los anuncios recompensados no están disponibles.');
}
