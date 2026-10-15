import 'reward_audit_service.dart';

String memberCardValueFromQr(String rawValue) {
  final value = rawValue.trim();
  final uri = Uri.tryParse(value);
  return uri?.queryParameters['memberCard'] ??
      uri?.queryParameters['cardNumber'] ??
      uri?.queryParameters['card'] ??
      value;
}

String coldBrewFigureQrPayload(String figureId) {
  if (!coldBrewFigures.any((figure) => figure.id == figureId)) {
    throw ArgumentError.value(figureId, 'figureId', 'La figurita no es válida.');
  }
  return 'coffee-wolves:cold-brew-figure:$figureId';
}

String parseColdBrewFigureQr(String rawValue) {
  final value = rawValue.trim();
  var figureId = value;
  const prefix = 'coffee-wolves:cold-brew-figure:';
  if (value.startsWith(prefix)) {
    figureId = value.substring(prefix.length);
  } else {
    final uri = Uri.tryParse(value);
    figureId = uri?.queryParameters['coldBrewFigure'] ??
        uri?.queryParameters['figureId'] ??
        uri?.queryParameters['figure'] ??
        value;
  }
  final figure = coldBrewFigures.where((candidate) => candidate.id == figureId);
  if (figure.isEmpty) {
    throw const FormatException(
      'El QR no corresponde a una figurita Cold Brew reconocida.',
    );
  }
  return figure.single.id;
}
