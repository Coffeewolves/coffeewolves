import 'dart:convert';

import 'reward_audit_service.dart';

String membershipCardQrPayload({
  required String memberId,
  required String memberName,
}) {
  final id = memberId.trim();
  final name = memberName.trim();
  if (!RegExp(r'^(CW-\d{6}|WLV-M-\d{6})$').hasMatch(id) ||
      name.isEmpty) {
    throw ArgumentError('El ID y el nombre del miembro deben ser válidos.');
  }
  return jsonEncode({
    'type': 'wolves_member_card',
    'memberId': id,
    'memberName': name,
  });
}

String memberCardValueFromQr(String rawValue) {
  final value = rawValue.trim();
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic> &&
        decoded['type'] == 'wolves_member_card') {
      final memberId = decoded['memberId'];
      final memberName = decoded['memberName'];
      if (memberId is String &&
          RegExp(r'^(CW-\d{6}|WLV-M-\d{6})$').hasMatch(memberId) &&
          memberName is String &&
          memberName.trim().isNotEmpty) {
        return memberId;
      }
      throw const FormatException('El QR de Member Card no es válido.');
    }
  } on FormatException {
    if (value.startsWith('{')) rethrow;
  }
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
