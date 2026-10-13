import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _publicEmailPattern = RegExp(
  r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
final _publicPhonePattern = RegExp(r'[0-9][0-9 ()+.-]{7,}[0-9]');
final _publicCoordinatesPattern =
    RegExp(r'-?[0-9]{1,3}\.[0-9]{3,}\s*,\s*-?[0-9]{1,3}\.[0-9]{3,}');

class LostPetMission {
  const LostPetMission({
    required this.id,
    required this.ownerUid,
    required this.petName,
    required this.species,
    required this.breed,
    required this.size,
    required this.color,
    required this.sex,
    required this.markings,
    required this.missingAt,
    required this.city,
    required this.area,
    required this.lastSeenArea,
    required this.description,
    required this.status,
    required this.photoCount,
    required this.createdAt,
    required this.updatedAt,
    required this.reunionStory,
    required this.shareReunion,
  });

  final String id;
  final String ownerUid;
  final String petName;
  final String species;
  final String breed;
  final String size;
  final String color;
  final String sex;
  final String markings;
  final DateTime missingAt;
  final String city;
  final String area;
  final String lastSeenArea;
  final String description;
  final String status;
  final int photoCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String reunionStory;
  final bool shareReunion;

  factory LostPetMission.fromMap(String id, Map<String, dynamic> data) {
    DateTime timestamp(String key) {
      final value = data[key];
      if (value is! Timestamp) {
        throw FormatException('El campo $key de la misión no es válido.');
      }
      return value.toDate();
    }

    String text(String key) => data[key] is String ? data[key] as String : '';

    return LostPetMission(
      id: id,
      ownerUid: text('ownerUid'),
      petName: text('petName'),
      species: text('species'),
      breed: text('breed'),
      size: text('size'),
      color: text('color'),
      sex: text('sex'),
      markings: text('markings'),
      missingAt: timestamp('missingAt'),
      city: text('city'),
      area: text('area'),
      lastSeenArea: text('lastSeenArea'),
      description: text('description'),
      status: text('status'),
      photoCount: data['photoCount'] is int ? data['photoCount'] as int : 0,
      createdAt: timestamp('createdAt'),
      updatedAt: timestamp('updatedAt'),
      reunionStory: text('reunionStory'),
      shareReunion: data['shareReunion'] == true,
    );
  }
}

class LostPetService {
  LostPetService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Map<String, Future<Uint8List?>> _photoCache = {};

  CollectionReference<Map<String, dynamic>> get _missions =>
      _firestore.collection('lostPetMissions');
  CollectionReference<Map<String, dynamic>> get _sightings =>
      _firestore.collection('lostPetSightings');
  CollectionReference<Map<String, dynamic>> get _favorites =>
      _firestore.collection('lostPetFavorites');
  CollectionReference<Map<String, dynamic>> get _contactRequests =>
      _firestore.collection('lostPetContactRequests');
  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('lostPetReports');

  User _verifiedUser() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      throw StateError('Inicia sesión y verifica tu correo para continuar.');
    }
    return user;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMissions() =>
      _missions.orderBy('updatedAt', descending: true).limit(50).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyMissions(String uid) =>
      _missions.where('ownerUid', isEqualTo: uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSightings() =>
      _sightings.orderBy('createdAt', descending: true).limit(50).snapshots();

  Future<LostPetMission?> getMission(String missionId) async {
    final document = await _missions.doc(missionId).get();
    if (!document.exists || document.data() == null) return null;
    return LostPetMission.fromMap(document.id, document.data()!);
  }

  Future<String> getPrivateIdentification(String missionId) async {
    final user = _verifiedUser();
    final mission = await _missions.doc(missionId).get();
    if (!mission.exists || mission.data()?['ownerUid'] != user.uid) {
      throw StateError('Solo quien publicó la misión puede ver esos detalles.');
    }
    final privateDetails = await _missions
        .doc(missionId)
        .collection('private')
        .doc('details')
        .get();
    return privateDetails.data()?['identification'] as String? ?? '';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMissionSightings(
    String missionId,
  ) =>
      _sightings.where('missionId', isEqualTo: missionId).limit(50).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchContactRequests(
    String missionId,
  ) =>
      _contactRequests
          .where('missionId', isEqualTo: missionId)
          .limit(50)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyContactRequests(
    String uid,
  ) =>
      _contactRequests.where('senderUid', isEqualTo: uid).limit(50).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFavorites(String uid) =>
      _favorites.where('userUid', isEqualTo: uid).limit(100).snapshots();

  Future<String> createMission({
    required Map<String, dynamic> fields,
    required List<Uint8List> photos,
  }) async {
    final user = _verifiedUser();
    _validatePhotos(photos, mustHave: true);
    final reference = _missions.doc();
    final batch = _firestore.batch();
    batch.set(reference, {
      ..._publicMissionFields(fields),
      'photoCount': photos.length,
      'ownerUid': user.uid,
      'status': 'active',
      'sightingsCount': 0,
      'reunionStory': '',
      'shareReunion': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      reference.collection('private').doc('details'),
      {
        'identification': (fields['identification'] as String).trim(),
        'reunionStory': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    for (var index = 0; index < photos.length; index++) {
      batch.set(
        reference.collection('photos').doc('$index'),
        _photoData(index, photos[index]),
      );
    }
    await batch.commit();
    return reference.id;
  }

  Future<void> updateMission({
    required String missionId,
    required Map<String, dynamic> fields,
    required List<Uint8List> photos,
  }) async {
    final user = _verifiedUser();
    _validatePhotos(photos, mustHave: true);
    final reference = _missions.doc(missionId);
    final mission = await reference.get();
    if (!mission.exists || mission.data()?['ownerUid'] != user.uid) {
      throw StateError('Solo quien publicó la misión puede editarla.');
    }
    final oldPhotoCount = mission.data()?['photoCount'] as int? ?? 0;
    final batch = _firestore.batch();
    batch.update(reference, {
      ..._publicMissionFields(fields),
      'photoCount': photos.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      reference.collection('private').doc('details'),
      {
        'identification': (fields['identification'] as String).trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    for (var index = 0; index < photos.length; index++) {
      batch.set(
        reference.collection('photos').doc('$index'),
        _photoData(index, photos[index]),
      );
    }
    for (var index = photos.length; index < oldPhotoCount; index++) {
      batch.delete(reference.collection('photos').doc('$index'));
    }
    await batch.commit();
    _clearPhotoCache(missionId);
  }

  void _validatePhotos(List<Uint8List> photos, {required bool mustHave}) {
    if ((mustHave && photos.isEmpty) || photos.length > 3) {
      throw ArgumentError('Agrega entre una y tres fotos.');
    }
    if (photos.any((photo) => photo.isEmpty || photo.length > 200 * 1024)) {
      throw ArgumentError('Cada foto debe pesar como máximo 200 KB.');
    }
  }

  Map<String, dynamic> _photoData(int index, Uint8List bytes) => {
        'index': index,
        'dataBase64': base64Encode(bytes),
      };

  Future<Uint8List?> getMissionPhoto(
    String missionId, {
    int index = 0,
  }) {
    final key = 'mission:$missionId:$index';
    return _photoCache.putIfAbsent(key, () async {
      final photo = await _missions
          .doc(missionId)
          .collection('photos')
          .doc('$index')
          .get();
      return _decodePhotoDocument(photo.data(), expectedIndex: index);
    });
  }

  Future<List<Uint8List>> getMissionPhotos(
    String missionId, {
    required int count,
  }) async {
    if (count < 0 || count > 3) {
      throw StateError('La misión contiene una cantidad de fotos no válida.');
    }
    final photos = await Future.wait([
      for (var index = 0; index < count; index++)
        getMissionPhoto(missionId, index: index),
    ]);
    if (photos.any((photo) => photo == null)) {
      throw StateError(
          'No se pudieron recuperar todas las fotos de la misión.');
    }
    return photos.cast<Uint8List>();
  }

  Uint8List? _decodePhotoDocument(
    Map<String, dynamic>? data, {
    required int expectedIndex,
  }) {
    if (data == null) return null;
    if (data['index'] != expectedIndex || data['dataBase64'] is! String) {
      throw StateError('Una foto guardada tiene un formato no válido.');
    }
    try {
      return base64Decode(data['dataBase64'] as String);
    } on FormatException {
      throw StateError('No se pudo leer una foto guardada.');
    }
  }

  void _clearPhotoCache(String missionId) {
    _photoCache.removeWhere((key, _) => key.startsWith('mission:$missionId:'));
  }

  Map<String, dynamic> _publicMissionFields(Map<String, dynamic> fields) {
    final publicFields = <String, dynamic>{
      'petName': (fields['petName'] as String).trim(),
      'species': fields['species'],
      'breed': (fields['breed'] as String).trim(),
      'size': fields['size'],
      'color': (fields['color'] as String).trim(),
      'sex': fields['sex'],
      'markings': (fields['markings'] as String).trim(),
      'missingAt': Timestamp.fromDate(fields['missingAt'] as DateTime),
      'city': (fields['city'] as String).trim(),
      'area': (fields['area'] as String).trim(),
      'lastSeenArea': (fields['lastSeenArea'] as String).trim(),
      'description': (fields['description'] as String).trim(),
      'publicationAuthorized': fields['publicationAuthorized'] == true,
      'informationIsAccurate': fields['informationIsAccurate'] == true,
    };
    _validatePublicText(publicFields, const [
      'petName',
      'breed',
      'color',
      'markings',
      'city',
      'area',
      'lastSeenArea',
      'description',
    ]);
    return publicFields;
  }

  Future<void> updateStatus(
    String missionId, {
    required String status,
    String reunionStory = '',
    bool shareReunion = false,
  }) async {
    _verifiedUser();
    if (!lostPetStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Estado no válido.');
    }
    final reference = _missions.doc(missionId);
    final batch = _firestore.batch();
    batch.update(reference, {
      'status': status,
      'reunionStory':
          status == 'reunited' && shareReunion ? reunionStory.trim() : '',
      'shareReunion': status == 'reunited' && shareReunion,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (status == 'reunited') {
      batch.set(
        reference.collection('private').doc('details'),
        {
          'reunionStory': reunionStory.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<String> createSighting({
    required String? missionId,
    required Map<String, dynamic> fields,
    Uint8List? photo,
  }) async {
    _verifiedUser();
    _validatePublicText(fields, const [
      'description',
      'color',
      'city',
      'area',
      'direction',
      'additionalInfo',
    ]);
    final reference = _sightings.doc();
    if (photo != null && photo.length > 200 * 1024) {
      throw ArgumentError('La foto del avistamiento supera 200 KB.');
    }
    final batch = _firestore.batch();
    batch.set(reference, {
      'missionId': missionId ?? '',
      'description': (fields['description'] as String).trim(),
      'species': fields['species'],
      'color': (fields['color'] as String).trim(),
      'size': fields['size'],
      'sightedAt': Timestamp.fromDate(fields['sightedAt'] as DateTime),
      'city': (fields['city'] as String).trim(),
      'area': (fields['area'] as String).trim(),
      'direction': (fields['direction'] as String).trim(),
      'additionalInfo': (fields['additionalInfo'] as String).trim(),
      'photoBase64': photo == null ? '' : base64Encode(photo),
      'verificationStatus': 'unverified',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return reference.id;
  }

  Future<void> createContactRequest({
    required String missionId,
    required String message,
  }) async {
    final user = _verifiedUser();
    final mission = await _missions.doc(missionId).get();
    if (!mission.exists || mission.data()?['ownerUid'] == user.uid) {
      throw StateError('No se puede enviar esta solicitud de contacto.');
    }
    final name = (user.displayName ?? 'Miembro de la Manada').trim();
    await _contactRequests.add({
      'missionId': missionId,
      'senderUid': user.uid,
      'senderName': name.length > 80 ? name.substring(0, 80) : name,
      'message': message.trim(),
      'status': 'new',
      'ownerReply': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> replyToContactRequest({
    required String requestId,
    required String reply,
  }) async {
    _verifiedUser();
    await _contactRequests.doc(requestId).update({
      'ownerReply': reply.trim(),
      'status': 'replied',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleFavorite({
    required String missionId,
    required bool isFavorite,
  }) async {
    final user = _verifiedUser();
    final reference = _favorites.doc('${user.uid}_$missionId');
    if (isFavorite) {
      await reference.delete();
    } else {
      await reference.set({
        'userUid': user.uid,
        'missionId': missionId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> reportMission({
    required String missionId,
    required String reason,
    String details = '',
  }) async {
    final user = _verifiedUser();
    await _reports.doc('${missionId}_${user.uid}').set({
      'missionId': missionId,
      'reporterUid': user.uid,
      'reason': reason,
      'details': details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _validatePublicText(Map<String, dynamic> fields, List<String> keys) {
    for (final key in keys) {
      final value = fields[key];
      if (value is String &&
          (_publicEmailPattern.hasMatch(value) ||
              _publicPhonePattern.hasMatch(value) ||
              _publicCoordinatesPattern.hasMatch(value))) {
        throw ArgumentError(
          'No publiques teléfonos, correos ni coordenadas exactas. '
          'Usa una zona aproximada y el contacto privado de la misión.',
        );
      }
    }
  }
}

const lostPetStatuses = {
  'active',
  'sightings',
  'verifying',
  'reunited',
  'closed',
};

int lostPetMatchScore({
  required String missionSpecies,
  required String sightingSpecies,
  required String missionColor,
  required String sightingColor,
  required String missionSize,
  required String sightingSize,
  required String missionCity,
  required String sightingCity,
  required DateTime missingAt,
  required DateTime sightedAt,
}) {
  var score = 0;
  bool matches(String first, String second) =>
      first.trim().isNotEmpty &&
      second.trim().isNotEmpty &&
      (first.toLowerCase().contains(second.toLowerCase()) ||
          second.toLowerCase().contains(first.toLowerCase()));
  if (matches(missionSpecies, sightingSpecies)) score += 4;
  if (matches(missionColor, sightingColor)) score += 2;
  if (matches(missionSize, sightingSize)) score += 1;
  if (matches(missionCity, sightingCity)) score += 2;
  if (!sightedAt.isBefore(missingAt.subtract(const Duration(days: 1)))) {
    score += 1;
  }
  return score;
}
