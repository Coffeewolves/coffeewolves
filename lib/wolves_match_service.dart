import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class MatchIcebreakerQuestion {
  const MatchIcebreakerQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<String> options;
}

class MatchIcebreakerContext {
  const MatchIcebreakerContext({
    required this.pairId,
    required this.ownPublicId,
    required this.peerPublicId,
  });

  final String pairId;
  final String ownPublicId;
  final String peerPublicId;
}

class WolvesMatchService {
  WolvesMatchService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const _interestOptions = {
    'Café de especialidad',
    'Eventos',
    'Música',
    'Lectura',
    'Naturaleza',
    'Mascotas',
    'Arte',
    'Viajes',
    'Conversaciones',
    'Deportes',
  };
  static const icebreakerQuestions = [
    MatchIcebreakerQuestion(
      id: 'q0',
      prompt: '¿Cuál sería tu plan ideal para compartir un café?',
      options: [
        'Conversar sin prisa',
        'Probar algo nuevo del menú',
        'Leer o trabajar en compañía',
        'Conocer a más personas',
      ],
    ),
    MatchIcebreakerQuestion(
      id: 'q1',
      prompt: '¿Qué detalle suele alegrarte el día?',
      options: [
        'Una buena canción',
        'Un mensaje inesperado',
        'Un paseo al aire libre',
        'Un momento con mi mascota',
      ],
    ),
    MatchIcebreakerQuestion(
      id: 'q2',
      prompt: '¿Qué te gustaría aprender por diversión?',
      options: [
        'Preparar café',
        'Tocar un instrumento',
        'Dibujar o pintar',
        'Cocinar algo nuevo',
      ],
    ),
    MatchIcebreakerQuestion(
      id: 'q3',
      prompt: '¿Cómo disfrutas más un día libre?',
      options: [
        'Aventura espontánea',
        'Plan tranquilo en casa',
        'Visitar un lugar nuevo',
        'Compartir con amigos',
      ],
    ),
    MatchIcebreakerQuestion(
      id: 'q4',
      prompt: 'Elige una conversación para empezar:',
      options: [
        '¿Qué música recomiendas?',
        '¿Cuál fue tu último plan favorito?',
        '¿Qué mascota te gustaría tener?',
        '¿Qué pequeño gusto nunca falla?',
      ],
    ),
  ];

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _participants =>
      _firestore.collection('wolvesMatchParticipants');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('wolvesMatchPublicProfiles');

  CollectionReference<Map<String, dynamic>> get _publicIds =>
      _firestore.collection('wolvesMatchPublicIds');

  CollectionReference<Map<String, dynamic>> get _pairs =>
      _firestore.collection('wolvesMatchPairs');

  CollectionReference<Map<String, dynamic>> _userPairs(String publicId) =>
      _firestore.collection('wolvesMatchUsers').doc(publicId).collection('pairs');

  CollectionReference<Map<String, dynamic>> get _blocks =>
      _firestore.collection('wolvesMatchBlocks');

  CollectionReference<Map<String, dynamic>> _icebreakerAnswers(String pairId) =>
      _firestore.collection('wolvesMatchIcebreakers').doc(pairId).collection(
            'answers',
          );

  Future<MatchIcebreakerContext> getIcebreakerContext(
    String peerPublicId,
  ) async {
    final user = await _requireEligibleUser();
    final own = await _participants.doc(user.uid).get();
    final ownPublicId = own.data()?['matchPublicId'] as String?;
    if (ownPublicId == null || own.data()?['status'] != 'active') {
      throw StateError('Activa tu perfil de WOLVES MATCH para jugar.');
    }
    _validatePublicId(peerPublicId, ownPublicId);
    final pairId = _pairId(ownPublicId, peerPublicId);
    final pair = await _pairs.doc(pairId).get();
    if (pair.data()?['status'] != 'mutual' ||
        !(pair.data()?['publicIds'] as List<dynamic>? ?? const [])
            .toSet()
            .containsAll([ownPublicId, peerPublicId])) {
      throw StateError('El juego solo está disponible para conexiones mutuas.');
    }
    return MatchIcebreakerContext(
      pairId: pairId,
      ownPublicId: ownPublicId,
      peerPublicId: peerPublicId,
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchIcebreakerAnswer({
    required MatchIcebreakerContext context,
    required String questionId,
    required String publicId,
  }) {
    return _icebreakerAnswers(context.pairId)
        .doc('${questionId}__$publicId')
        .snapshots();
  }

  Future<void> submitIcebreakerAnswer({
    required MatchIcebreakerContext context,
    required String questionId,
    required int answerIndex,
  }) async {
    final question = icebreakerQuestions.where((item) => item.id == questionId);
    if (question.isEmpty ||
        answerIndex < 0 ||
        answerIndex >= question.first.options.length) {
      throw ArgumentError('La respuesta no es válida.');
    }
    final user = await _requireEligibleUser();
    final ownReference = _participants.doc(user.uid);
    final pairReference = _pairs.doc(context.pairId);
    final answerReference = _icebreakerAnswers(context.pairId)
        .doc('${questionId}__${context.ownPublicId}');

    await _firestore.runTransaction<void>((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(ownReference),
        transaction.get(pairReference),
        transaction.get(answerReference),
      ]);
      final own = snapshots[0].data();
      final pair = snapshots[1].data();
      if (own?['matchPublicId'] != context.ownPublicId ||
          own?['status'] != 'active' ||
          pair?['status'] != 'mutual' ||
          !(pair?['publicIds'] as List<dynamic>? ?? const [])
              .toSet()
              .containsAll([context.ownPublicId, context.peerPublicId])) {
        throw StateError('La conexión ya no está disponible para jugar.');
      }
      if (snapshots[2].exists) {
        throw StateError('Ya respondiste esta pregunta.');
      }
      transaction.set(answerReference, {
        'questionId': questionId,
        'publicId': context.ownPublicId,
        'answerIndex': answerIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Map<String, dynamic>> getState() async {
    final user = await _requireEligibleUser();
    final participantRef = _participants.doc(user.uid);
    final participantSnapshot = await participantRef.get();
    if (!participantSnapshot.exists) {
      final account = await _firestore.collection('users').doc(user.uid).get();
      return _emptyState(
        account.data()?['displayName'] as String? ??
            user.displayName?.trim() ??
            '',
      );
    }

    final participant = participantSnapshot.data()!;
    final publicId = participant['matchPublicId'] as String?;
    if (publicId == null || publicId.isEmpty) {
      throw StateError('El perfil de WOLVES MATCH no tiene identificador.');
    }
    if (participant['status'] == 'active') {
      await _publishLegacyProfile(participantRef, publicId);
    }

    final pairs = await _userPairs(publicId).limit(100).get();
    final relatedIds = <String>{};
    final incoming = <Map<String, dynamic>>[];
    final outgoing = <Map<String, dynamic>>[];
    final connections = <Map<String, dynamic>>[];

    for (final pairSnapshot in pairs.docs) {
      final pair = pairSnapshot.data();
      final otherId = pair['peerPublicId'] as String?;
      if (otherId == null || otherId.isEmpty) continue;
      relatedIds.add(otherId);
      if (participant['status'] != 'active') continue;
      final peerSnapshot = await _publicProfiles.doc(otherId).get();
      if (!peerSnapshot.exists) continue;
      final peer = peerSnapshot.data()!;
      if (peer['status'] != 'active' ||
          !_intentionsCompatible(
            participant['intention'] as String?,
            peer['intention'] as String?,
          )) {
        continue;
      }
      final profile = _publicProfile(peerSnapshot.id, peer);
      if (pair['status'] == 'mutual') {
        connections.add(profile);
      } else if (pair['status'] == 'pending') {
        if (pair['interestFromPublicId'] == publicId) {
          outgoing.add(profile);
        } else {
          incoming.add(profile);
        }
      }
    }

    final recommendations = <Map<String, dynamic>>[];
    if (participant['status'] == 'active') {
      final candidates = await _publicProfiles
          .where('status', isEqualTo: 'active')
          .limit(30)
          .get();
      for (final candidateSnapshot in candidates.docs) {
        if (candidateSnapshot.id == publicId ||
            relatedIds.contains(candidateSnapshot.id)) {
          continue;
        }
        final candidate = candidateSnapshot.data();
        if (!_intentionsCompatible(
          participant['intention'] as String?,
          candidate['intention'] as String?,
        )) {
          continue;
        }
        final blockedByMe = await _blockReference(
          publicId,
          candidateSnapshot.id,
        ).get();
        final blockedMe = await _blockReference(
          candidateSnapshot.id,
          publicId,
        ).get();
        if (!blockedByMe.exists && !blockedMe.exists) {
          recommendations.add(
            _publicProfile(candidateSnapshot.id, candidate),
          );
        }
      }
    }

    return {
      'status': participant['status'] as String? ?? 'inactive',
      'displayName': participant['displayName'] as String? ?? '',
      'bio': participant['bio'] as String? ?? '',
      'interests': participant['interests'] as List<dynamic>? ?? const [],
      'intention': participant['intention'] as String?,
      'recommendations': recommendations,
      'incoming': incoming,
      'outgoing': outgoing,
      'connections': connections,
    };
  }

  Future<void> saveProfile({
    required String status,
    required String displayName,
    required String bio,
    required String intention,
    required List<String> interests,
    bool consent = false,
  }) async {
    final user = await _requireEligibleUser();
    if (!{'configuring', 'active', 'paused', 'left'}.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final normalizedName = displayName.trim();
    final normalizedBio = bio.trim();
    final normalizedInterests = interests.toSet().toList();
    if (status == 'configuring' || status == 'active') {
      _validateProfile(
        displayName: normalizedName,
        bio: normalizedBio,
        intention: intention,
        interests: normalizedInterests,
      );
    }
    if (status == 'active' && !consent) {
      throw StateError(
        'Confirma tu consentimiento para activar WOLVES MATCH.',
      );
    }

    final participantRef = _participants.doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(participantRef);
      final current = currentSnapshot.data();
      final publicId = current?['matchPublicId'] as String? ?? _newPublicId();
      final publicRef = _publicProfiles.doc(publicId);
      if (!currentSnapshot.exists) {
        transaction.set(_publicIds.doc(publicId), {'uid': user.uid});
      }
      final now = FieldValue.serverTimestamp();
      final createdAt = current?['createdAt'] ?? FieldValue.serverTimestamp();
      final consentAt = status == 'active'
          ? FieldValue.serverTimestamp()
          : current?['consentAt'];
      final participant = <String, dynamic>{
        'displayName': normalizedName.isEmpty
            ? user.displayName?.trim() ?? ''
            : normalizedName,
        'bio': normalizedBio,
        'intention': intention,
        'interests': normalizedInterests,
        'status': status,
        'matchPublicId': publicId,
        'consentAt': consentAt,
        'createdAt': createdAt,
        'updatedAt': now,
      };
      transaction.set(participantRef, participant);
      transaction.set(publicRef, {
        'displayName': participant['displayName'],
        'bio': normalizedBio,
        'intention': intention,
        'interests': normalizedInterests,
        'status': status,
        'updatedAt': now,
      });
    });
  }

  Future<String> sendInterest(String profileId) async {
    final user = await _requireEligibleUser();
    final ownRef = _participants.doc(user.uid);
    final own = await ownRef.get();
    final ownId = own.data()?['matchPublicId'] as String?;
    if (ownId == null || own.data()?['status'] != 'active') {
      throw StateError('Activa tu perfil para mostrar interés.');
    }
    _validatePublicId(profileId, ownId);
    final targetRef = _publicProfiles.doc(profileId);
    final pairRef = _pairs.doc(_pairId(ownId, profileId));
    final ownBlockRef = _blockReference(ownId, profileId);
    final targetBlockRef = _blockReference(profileId, ownId);

    return _firestore.runTransaction<String>((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(targetRef),
        transaction.get(pairRef),
        transaction.get(ownBlockRef),
        transaction.get(targetBlockRef),
      ]);
      final target = snapshots[0].data();
      final existingPair = snapshots[1].data();
      if (target == null ||
          target['status'] != 'active' ||
          snapshots[2].exists ||
          snapshots[3].exists ||
          !_intentionsCompatible(
            own.data()?['intention'] as String?,
            target['intention'] as String?,
          )) {
        throw StateError(
            'La conexión ya no está disponible o no es compatible.');
      }
      if (existingPair?['status'] == 'mutual') return 'mutual';
      if ({'blocked', 'declined'}.contains(existingPair?['status'])) {
        throw StateError('Este perfil ya no está disponible.');
      }
      final publicIds = _sortedIds(ownId, profileId);
      if (existingPair?['status'] == 'pending') {
        if (existingPair?['interestFromPublicId'] == ownId) {
          return 'pending';
        }
        transaction.update(pairRef, {
          'status': 'mutual',
          'decidedByPublicId': ownId,
          'mutualAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _writePairViews(
          transaction,
          ownId: ownId,
          peerId: profileId,
          status: 'mutual',
          interestFromPublicId:
              existingPair!['interestFromPublicId'] as String,
        );
        return 'mutual';
      }
      transaction.set(
        pairRef,
        {
          'publicIds': publicIds,
          'status': 'pending',
          'interestFromPublicId': ownId,
          'decidedByPublicId': ownId,
          'createdAt':
              existingPair?['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _writePairViews(
        transaction,
        ownId: ownId,
        peerId: profileId,
        status: 'pending',
        interestFromPublicId: ownId,
      );
      return 'pending';
    });
  }

  Future<void> respondToInterest({
    required String profileId,
    required bool accept,
  }) async {
    final user = await _requireEligibleUser();
    final own = await _participants.doc(user.uid).get();
    final ownId = own.data()?['matchPublicId'] as String?;
    if (ownId == null || own.data()?['status'] != 'active') {
      throw StateError('Activa tu perfil para responder al interés.');
    }
    _validatePublicId(profileId, ownId);
    final pairRef = _pairs.doc(_pairId(ownId, profileId));
    final targetRef = _publicProfiles.doc(profileId);
    final ownBlockRef = _blockReference(ownId, profileId);
    final targetBlockRef = _blockReference(profileId, ownId);
    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(pairRef),
        transaction.get(targetRef),
        transaction.get(ownBlockRef),
        transaction.get(targetBlockRef),
      ]);
      final pair = snapshots[0].data();
      final target = snapshots[1].data();
      if (pair == null ||
          pair['status'] != 'pending' ||
          pair['interestFromPublicId'] == ownId ||
          target?['status'] != 'active' ||
          snapshots[2].exists ||
          snapshots[3].exists) {
        throw StateError('Este interés ya no está disponible.');
      }
      if (accept &&
          !_intentionsCompatible(
            own.data()?['intention'] as String?,
            target?['intention'] as String?,
          )) {
        throw StateError('Las intenciones ya no son compatibles.');
      }
      transaction.update(pairRef, {
        'status': accept ? 'mutual' : 'declined',
        'decidedByPublicId': ownId,
        if (accept) 'mutualAt': FieldValue.serverTimestamp(),
        if (!accept) 'decidedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _writePairViews(
        transaction,
        ownId: ownId,
        peerId: profileId,
        status: accept ? 'mutual' : 'declined',
        interestFromPublicId: pair['interestFromPublicId'] as String,
      );
    });
  }

  Future<void> dismissProfile(String profileId) async {
    final user = await _requireEligibleUser();
    final own = await _participants.doc(user.uid).get();
    final ownId = own.data()?['matchPublicId'] as String?;
    if (ownId == null || own.data()?['status'] != 'active') {
      throw StateError('Activa tu perfil para descartar recomendaciones.');
    }
    _validatePublicId(profileId, ownId);
    final pairRef = _pairs.doc(_pairId(ownId, profileId));
    final targetRef = _publicProfiles.doc(profileId);
    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(pairRef),
        transaction.get(targetRef),
      ]);
      final pair = snapshots[0].data();
      if (pair?['status'] == 'mutual') {
        throw StateError(
          'Una conexión mutua no puede descartarse como recomendación.',
        );
      }
      if (pair?['status'] == 'blocked') return;
      if (snapshots[1].data()?['status'] != 'active') {
        throw StateError('Este perfil ya no está disponible.');
      }
      transaction.set(
        pairRef,
        {
          'publicIds': _sortedIds(ownId, profileId),
          'status': 'declined',
          'interestFromPublicId': ownId,
          'decidedByPublicId': ownId,
          'createdAt': pair?['createdAt'] ?? FieldValue.serverTimestamp(),
          'decidedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _writePairViews(
        transaction,
        ownId: ownId,
        peerId: profileId,
        status: 'declined',
        interestFromPublicId: ownId,
      );
    });
  }

  Future<void> blockProfile(String profileId) async {
    final user = await _requireEligibleUser();
    final own = await _participants.doc(user.uid).get();
    final ownId = own.data()?['matchPublicId'] as String?;
    if (ownId == null) throw StateError('No se encontró tu perfil de Match.');
    _validatePublicId(profileId, ownId);
    final blockRef = _blockReference(ownId, profileId);
    final pairRef = _pairs.doc(_pairId(ownId, profileId));
    final targetRef = _publicProfiles.doc(profileId);
    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(blockRef),
        transaction.get(pairRef),
        transaction.get(targetRef),
      ]);
      if (!snapshots[2].exists) {
        throw StateError('Este perfil ya no está disponible.');
      }
      final pair = snapshots[1].data();
      if (!snapshots[0].exists) {
        transaction.set(blockRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(
        pairRef,
        {
          'publicIds': _sortedIds(ownId, profileId),
          'status': 'blocked',
          'interestFromPublicId': ownId,
          'decidedByPublicId': ownId,
          'createdAt': pair?['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _writePairViews(
        transaction,
        ownId: ownId,
        peerId: profileId,
        status: 'blocked',
        interestFromPublicId: ownId,
      );
    });
  }

  void _writePairViews(
    Transaction transaction, {
    required String ownId,
    required String peerId,
    required String status,
    required String interestFromPublicId,
  }) {
    final pairId = _pairId(ownId, peerId);
    final updatedAt = FieldValue.serverTimestamp();
    transaction.set(_userPairs(ownId).doc(pairId), {
      'peerPublicId': peerId,
      'status': status,
      'interestFromPublicId': interestFromPublicId,
      'updatedAt': updatedAt,
    });
    transaction.set(_userPairs(peerId).doc(pairId), {
      'peerPublicId': ownId,
      'status': status,
      'interestFromPublicId': interestFromPublicId,
      'updatedAt': updatedAt,
    });
  }

  Future<void> reportProfile({
    required String profileId,
    required String reason,
    required String details,
  }) async {
    final user = await _requireEligibleUser();
    final own = await _participants.doc(user.uid).get();
    final ownId = own.data()?['matchPublicId'] as String?;
    if (ownId == null) throw StateError('No se encontró tu perfil de Match.');
    _validatePublicId(profileId, ownId);
    if (!{'inappropriate', 'fake', 'harassment', 'other'}.contains(reason) ||
        details.trim().length > 500) {
      throw ArgumentError('El reporte no es válido.');
    }
    final target = await _publicProfiles.doc(profileId).get();
    if (!target.exists) throw StateError('Este perfil ya no está disponible.');
    await _firestore.collection('wolvesMatchReports').add({
      'reporterUid': user.uid,
      'targetPublicId': profileId,
      'reason': reason,
      'details': details.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<User> _requireEligibleUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para continuar.');
    }
    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null || !refreshedUser.emailVerified) {
      throw StateError('Verifica tu correo para usar WOLVES MATCH.');
    }
    await refreshedUser.getIdToken(true);
    final account = await _firestore.collection('users').doc(user.uid).get();
    if (!account.exists) {
      throw StateError('Completa tu perfil antes de entrar a WOLVES MATCH.');
    }
    final birthDate =
        account.data()?['birthDate'] ?? account.data()?['dateOfBirth'];
    if (!_isAdult(birthDate)) {
      throw StateError(
        'WOLVES MATCH está disponible solo para miembros mayores de 18 años '
        'con fecha de nacimiento registrada.',
      );
    }
    return refreshedUser;
  }

  bool _isAdult(Object? value) {
    if (value is! String) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year.toString().padLeft(4, '0') != value.split('-').first) {
      return false;
    }
    final today = DateTime.now();
    var age = today.year - parsed.year;
    if (today.month < parsed.month ||
        (today.month == parsed.month && today.day < parsed.day)) {
      age--;
    }
    return age >= 18;
  }

  Future<void> _publishLegacyProfile(
    DocumentReference<Map<String, dynamic>> participantRef,
    String publicId,
  ) async {
    final publicRef = _publicProfiles.doc(publicId);
    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(participantRef),
        transaction.get(publicRef),
      ]);
      final current = snapshots[0];
      if (!current.exists ||
          current.data()?['status'] != 'active' ||
          current.data()?['matchPublicId'] != publicId) {
        return;
      }
      final publicProfile = {
        'displayName': current.data()?['displayName'] ?? '',
        'bio': current.data()?['bio'] ?? '',
        'intention': current.data()?['intention'] ?? '',
        'interests': current.data()?['interests'] ?? const <String>[],
        'status': 'active',
      };
      final existing = snapshots[1].data();
      final alreadyPublished = existing != null &&
          publicProfile.entries.every(
            (entry) => _sameValue(existing[entry.key], entry.value),
          );
      if (!alreadyPublished) {
        transaction.set(publicRef, {
          ...publicProfile,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  bool _sameValue(Object? first, Object? second) {
    if (first is List && second is List) {
      return listEquals(first, second);
    }
    return first == second;
  }

  DocumentReference<Map<String, dynamic>> _blockReference(
    String ownerId,
    String blockedId,
  ) =>
      _blocks.doc(ownerId).collection('users').doc(blockedId);

  Map<String, dynamic> _emptyState(String displayName) => {
        'status': 'inactive',
        'displayName': displayName,
        'bio': '',
        'interests': <String>[],
        'intention': null,
        'recommendations': <Map<String, dynamic>>[],
        'incoming': <Map<String, dynamic>>[],
        'outgoing': <Map<String, dynamic>>[],
        'connections': <Map<String, dynamic>>[],
      };

  Map<String, dynamic> _publicProfile(
    String id,
    Map<String, dynamic> data,
  ) =>
      {
        'id': id,
        'displayName': data['displayName'] as String? ?? '',
        'bio': data['bio'] as String? ?? '',
        'interests': data['interests'] as List<dynamic>? ?? const [],
        'intention': data['intention'] as String?,
      };

  String _newPublicId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  String _pairId(String idA, String idB) => _sortedIds(idA, idB).join('__');

  List<String> _sortedIds(String idA, String idB) {
    final ids = [idA, idB]..sort();
    return ids;
  }

  void _validatePublicId(String id, String ownId) {
    if (id == ownId || !RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(id)) {
      throw ArgumentError('Perfil no válido.');
    }
  }

  void _validateProfile({
    required String displayName,
    required String bio,
    required String intention,
    required List<String> interests,
  }) {
    final profileText = '$displayName\n$bio';
    final includesPrivateContact =
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false)
                .hasMatch(profileText) ||
            RegExp(r'\+?\d[\d\s().-]{8,}\d').hasMatch(profileText) ||
            RegExp(r'\b-?\d{1,3}\.\d{3,}\s*[,;]\s*-?\d{1,3}\.\d{3,}\b')
                .hasMatch(profileText) ||
            RegExp(
              r'\b(?:calle|av(?:enida)?|pasaje|carretera|street|avenue)\s+(?:[a-z]+\s+)?\d+',
              caseSensitive: false,
            ).hasMatch(profileText);
    if (!{'friendship', 'romantic', 'both'}.contains(intention) ||
        displayName.length < 2 ||
        displayName.length > 40 ||
        bio.length > 180 ||
        interests.length > 5 ||
        interests.any((interest) => !_interestOptions.contains(interest)) ||
        includesPrivateContact) {
      throw ArgumentError(
        includesPrivateContact
            ? 'No incluyas correo, teléfono ni ubicación exacta en el perfil.'
            : 'Revisa el nombre, la intención y los intereses de tu perfil.',
      );
    }
  }

  bool _intentionsCompatible(String? a, String? b) {
    const accepted = {
      'friendship': {'friendship'},
      'romantic': {'romantic'},
      'both': {'friendship', 'romantic'},
    };
    final acceptedA = accepted[a];
    final acceptedB = accepted[b];
    return acceptedA != null &&
        acceptedB != null &&
        acceptedA.intersection(acceptedB).isNotEmpty;
  }
}
