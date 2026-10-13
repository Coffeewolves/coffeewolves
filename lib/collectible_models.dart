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

enum CollectibleAlbumType { cup, plush }

class CollectibleAlbumEntry {
  const CollectibleAlbumEntry({
    required this.id,
    required this.name,
    required this.breedId,
    required this.breedName,
    required this.type,
    required this.modelCode,
    required this.unlocked,
    this.methodId,
    this.imageAsset,
  });

  final String id;
  final String name;
  final String breedId;
  final String breedName;
  final CollectibleAlbumType type;
  final String modelCode;
  final bool unlocked;
  final String? methodId;
  final String? imageAsset;
}

const collectibleAlbumBreeds = <({String id, String name, String cupCode})>[
  (id: 'pomi', name: 'Pomerania · Pomi', cupCode: 'CW-CUP-007'),
  (id: 'samoyed', name: 'Samoyedo', cupCode: 'CW-CUP-008'),
  (id: 'husky', name: 'Husky', cupCode: 'CW-CUP-009'),
];

const collectibleCupMethods = <({String id, String name})>[
  (id: 'dripper-v60', name: 'Dripper V60'),
  (id: 'chemex', name: 'Chemex'),
  (id: 'origami', name: 'Origami'),
  (id: 'aeropress', name: 'Aeropress'),
  (id: 'prensa-francesa', name: 'Prensa francesa'),
  (id: 'sifon-japones', name: 'Sifón japonés'),
  (id: 'sifon-belga', name: 'Sifón belga'),
  (id: 'cold-brew', name: 'Cold Brew'),
  (id: 'nitro-cold-brew', name: 'Nitro Cold Brew'),
];

List<CollectibleAlbumEntry> buildCollectibleAlbum({
  Set<String> ownedModelCodes = const {},
  Set<String> ownedCupMethodIds = const {},
}) {
  final entries = <CollectibleAlbumEntry>[];
  const plushModels = [
    ['CW-PLUSH-001', 'El Alfa'],
    ['CW-PLUSH-002', 'El Explorador'],
    ['CW-PLUSH-003', 'El Elegante'],
    ['CW-PLUSH-004', 'El Nómada'],
    ['CW-PLUSH-005', 'El Aventurero'],
    ['CW-PLUSH-006', 'El Protector'],
  ];

  for (var breedIndex = 0;
      breedIndex < collectibleAlbumBreeds.length;
      breedIndex++) {
    final breed = collectibleAlbumBreeds[breedIndex];
    for (final method in collectibleCupMethods) {
      entries.add(
        CollectibleAlbumEntry(
          id: 'cup-${breed.id}-${method.id}',
          name: method.name,
          breedId: breed.id,
          breedName: breed.name,
          type: CollectibleAlbumType.cup,
          modelCode: breed.cupCode,
          methodId: method.id,
          unlocked: ownedModelCodes.contains(breed.cupCode) &&
              ownedCupMethodIds.contains(method.id),
        ),
      );
    }

    for (var plushIndex = 0; plushIndex < 2; plushIndex++) {
      final plush = plushModels[breedIndex * 2 + plushIndex];
      entries.add(
        CollectibleAlbumEntry(
          id: 'plush-${breed.id}-${plushIndex + 1}',
          name: plush[1],
          breedId: breed.id,
          breedName: breed.name,
          type: CollectibleAlbumType.plush,
          modelCode: plush[0],
          unlocked: ownedModelCodes.contains(plush[0]) ||
              plushIndex == 0 &&
                  ownedModelCodes.contains('CW-PLUSH-00${breedIndex + 7}'),
        ),
      );
    }
  }

  return List.unmodifiable(entries);
}

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
