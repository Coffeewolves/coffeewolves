import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CoffeePupGameService {
  CoffeePupGameService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(
    String sessionId,
  ) {
    return _firestore.collection('game_sessions').doc(sessionId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProgress(String uid) {
    return _firestore.collection('coffeePupProfiles').doc(uid).snapshots();
  }

  Future<String> startGame({
    required String profileId,
    required String gameType,
  }) async {
    if (!const {'trivia', 'preferences'}.contains(gameType)) {
      throw ArgumentError.value(
          gameType, 'gameType', 'Tipo de juego inválido.');
    }
    final result = await _functions
        .httpsCallable('startCoffeePupGame')
        .call<Map<String, dynamic>>({
      'profileId': profileId,
      'gameType': gameType,
    });
    final sessionId = result.data['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw StateError('El servidor no devolvió una partida válida.');
    }
    return sessionId;
  }

  Future<Map<String, dynamic>> submitAnswer({
    required String sessionId,
    required String questionId,
    required int answerIndex,
  }) async {
    final result = await _functions
        .httpsCallable('submitCoffeePupAnswer')
        .call<Map<String, dynamic>>({
      'sessionId': sessionId,
      'questionId': questionId,
      'answerIndex': answerIndex,
    });
    return result.data;
  }
}
