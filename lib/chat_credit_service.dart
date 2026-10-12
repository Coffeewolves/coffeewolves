import 'package:cloud_firestore/cloud_firestore.dart';

const startingChatCredits = 10;

class ChatCreditsExhaustedException implements Exception {
  const ChatCreditsExhaustedException();

  @override
  String toString() => 'No tienes créditos de mensaje disponibles.';
}

class ChatMessageResult {
  const ChatMessageResult({required this.credits});

  final int credits;
}

class ChatCreditService {
  ChatCreditService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<int> loadCredits({required String uid}) async {
    if (uid.isEmpty) throw ArgumentError.value(uid, 'uid');
    final profileReference = _firestore.collection('users').doc(uid);
    return _firestore.runTransaction<int>((transaction) async {
      final profile = await transaction.get(profileReference);
      if (!profile.exists) {
        throw StateError('No se encontró tu perfil de usuario.');
      }
      final data = profile.data()!;
      if (!data.containsKey('messageCredits')) {
        transaction.update(profileReference, {
          'messageCredits': startingChatCredits,
          'messageCreditsUpdatedAt': FieldValue.serverTimestamp(),
        });
        return startingChatCredits;
      }
      final credits = data['messageCredits'];
      if (credits is! int || credits < 0) {
        throw StateError('El saldo de créditos no es válido.');
      }
      return credits;
    });
  }

  Future<ChatMessageResult> sendMessage({
    required String uid,
    required String messageId,
    required String text,
    required String matchProfileId,
    required String matchName,
  }) async {
    final normalizedText = text.trim();
    final normalizedName = matchName.trim();
    if (uid.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(messageId) ||
        normalizedText.isEmpty ||
        normalizedText.length > 500 ||
        !RegExp(r'^\d{1,8}$').hasMatch(matchProfileId) ||
        normalizedName.isEmpty ||
        normalizedName.length > 80) {
      throw ArgumentError('El mensaje no es válido.');
    }

    final profileReference = _firestore.collection('users').doc(uid);
    final messageReference =
        profileReference.collection('chatMessages').doc(messageId);
    return _firestore.runTransaction<ChatMessageResult>((transaction) async {
      final profile = await transaction.get(profileReference);
      final existingMessage = await transaction.get(messageReference);
      if (!profile.exists) {
        throw StateError('No se encontró tu perfil de usuario.');
      }

      final data = profile.data()!;
      final credits = data['messageCredits'];
      if (credits is! int || credits < 0) {
        throw StateError('Actualiza el saldo de créditos e inténtalo de nuevo.');
      }
      if (existingMessage.exists) {
        final existing = existingMessage.data()!;
        if (existing['text'] != normalizedText ||
            existing['matchProfileId'] != matchProfileId ||
            existing['matchName'] != normalizedName) {
          throw StateError('El identificador del mensaje ya fue utilizado.');
        }
        return ChatMessageResult(credits: credits);
      }
      if (credits == 0) throw const ChatCreditsExhaustedException();

      final updatedCredits = credits - 1;
      transaction.update(profileReference, {
        'messageCredits': updatedCredits,
        'messageCreditsUpdatedAt': FieldValue.serverTimestamp(),
        'lastChatMessageId': messageId,
      });
      transaction.set(messageReference, {
        'text': normalizedText,
        'matchProfileId': matchProfileId,
        'matchName': normalizedName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ChatMessageResult(credits: updatedCredits);
    });
  }
}
