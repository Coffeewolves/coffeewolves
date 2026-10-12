import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class MischiefWallService {
  MischiefWallService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('mischiefPosts');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> createPost({
    required Uint8List imageBytes,
    required String dogName,
    required String description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Inicia sesión con una cuenta para publicar.');
    }
    if (!user.emailVerified) {
      throw StateError('Verifica tu correo antes de publicar.');
    }
    if (imageBytes.isEmpty || imageBytes.length > 200 * 1024) {
      throw ArgumentError.value(
        imageBytes.length,
        'imageBytes',
        'La imagen debe pesar como máximo 200 KB.',
      );
    }
    if (dogName.trim().isEmpty ||
        dogName.trim().length > 40 ||
        description.trim().isEmpty ||
        description.trim().length > 300) {
      throw ArgumentError('Completa los datos de la publicación.');
    }
    final post = _posts.doc();
    final photoPath = 'mischief-posts/${user.uid}/${post.id}.jpg';
    final photoReference = _storage.ref(photoPath);
    try {
      await photoReference.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final photoUrl = await photoReference.getDownloadURL();
      final ownerName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'Miembro de la manada';
      await post.set({
        'ownerUid': user.uid,
        'ownerName':
            ownerName.length > 80 ? ownerName.substring(0, 80) : ownerName,
        'dogName': dogName.trim(),
        'description': description.trim(),
        'photoPath': photoPath,
        'photoUrl': photoUrl,
        'innocentVotes': 0,
        'guiltyVotes': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      try {
        await photoReference.delete();
      } on FirebaseException {
        // The upload can fail before a Storage object exists.
      }
      rethrow;
    }
  }

  Future<void> vote({
    required String postId,
    required String choice,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Inicia sesión para votar.');
    }
    if (choice != 'innocent' && choice != 'guilty') {
      throw ArgumentError.value(choice, 'choice', 'Voto no válido.');
    }

    await _functions.httpsCallable('voteMischiefPost').call({
      'postId': postId,
      'choice': choice,
    });
  }

  Future<void> reportPost(String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Inicia sesión para reportar una publicación.');
    }
    await _firestore
        .collection('mischiefReports')
        .doc('${postId}_${user.uid}')
        .set({
      'postId': postId,
      'reporterUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
