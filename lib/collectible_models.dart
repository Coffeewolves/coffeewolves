const collectibleModelsByCategory = <String, Map<String, String>>{
  'PLUSH': {
    'CW-PLUSH-001': 'El Alfa',
    'CW-PLUSH-002': 'El Explorador',
    'CW-PLUSH-003': 'El Elegante',
    'CW-PLUSH-004': 'El Nómada',
    'CW-PLUSH-005': 'El Aventurero',
    'CW-PLUSH-006': 'El Protector',
  },
  'CUPS': {
    'CW-CUP-007': 'POMERANIAN',
    'CW-CUP-008': 'SAMOYED',
    'CW-CUP-009': 'HUSKY',
  },
};

const collectibleModelNames = <String, String>{
  'CW-PLUSH-001': 'El Alfa',
  'CW-PLUSH-002': 'El Explorador',
  'CW-PLUSH-003': 'El Elegante',
  'CW-PLUSH-004': 'El Nómada',
  'CW-PLUSH-005': 'El Aventurero',
  'CW-PLUSH-006': 'El Protector',
  // Keep previously issued PLUSH codes valid for existing records.
  'CW-PLUSH-007': 'POMI',
  'CW-PLUSH-008': 'SAMO',
  'CW-PLUSH-009': 'HUSKY',
  'CW-CUP-007': 'POMERANIAN',
  'CW-CUP-008': 'SAMOYED',
  'CW-CUP-009': 'HUSKY',
};

bool isValidCollectibleModel(String modelCode) =>
    collectibleModelNames.containsKey(modelCode);

bool isValidCollectibleModelUnit(String code) {
  final match = RegExp(
    r'^(CW-(?:PLUSH-00[1-9]|CUP-00[7-9]))-[0-9]{4}$',
  ).firstMatch(code);
  return match != null &&
      isValidCollectibleModel(match.group(1)!) &&
      int.parse(code.substring(code.length - 4)) > 0;
}
