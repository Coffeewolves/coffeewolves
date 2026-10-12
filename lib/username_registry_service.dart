import 'package:cloud_firestore/cloud_firestore.dart';

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();

  @override
  String toString() => 'Ese Username ya está en uso. Elige otro.';
}

class UsernameRegistryService {
  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');

  static String normalize(String username) => username.trim().toLowerCase();

  static String? validate(String username) {
    if (!_usernamePattern.hasMatch(username.trim())) {
      return 'Usa de 3 a 20 letras, números, puntos, guiones o guion bajo; sin espacios.';
    }
    return null;
  }

  static Future<void> reserveInTransaction({
    required Transaction transaction,
    required FirebaseFirestore firestore,
    required String uid,
    required String username,
    required String role,
    String? previousUsername,
  }) async {
    final normalized = normalize(username);
    final previous =
        previousUsername == null ? '' : normalize(previousUsername);
    final newReference =
        firestore.collection('usernameRegistry').doc(normalized);
    final oldReference = previous.isEmpty || previous == normalized
        ? null
        : firestore.collection('usernameRegistry').doc(previous);

    final oldSnapshot =
        oldReference == null ? null : await transaction.get(oldReference);
    final newSnapshot = await transaction.get(newReference);
    final existingOwner = newSnapshot.data()?['uid'];
    if (newSnapshot.exists && existingOwner != uid) {
      throw const UsernameAlreadyTakenException();
    }

    if (oldReference != null &&
        oldSnapshot?.exists == true &&
        oldSnapshot?.data()?['uid'] == uid) {
      transaction.delete(oldReference);
    }
    transaction.set(newReference, {
      'uid': uid,
      'username': normalized,
      'role': role,
    });
  }
}
