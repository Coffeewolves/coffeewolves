import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class MischiefWallService {
  MischiefWallService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('mischiefPosts');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() {
    return _posts.orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  Future<void> createPost({
    required Uint8List imageBytes,
    required String dogName,
    required String description,
    void Function(String stage)? onProgress,
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
    var postWriteStarted = false;
    try {
      onProgress?.call('SUBIENDO FOTO…');
      final uploadTask = photoReference.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await uploadTask.timeout(
        const Duration(seconds: 45),
        onTimeout: () async {
          await uploadTask.cancel().timeout(const Duration(seconds: 5));
          throw TimeoutException('La subida de la foto tardó demasiado.');
        },
      );
      onProgress?.call('PREPARANDO PUBLICACIÓN…');
      final photoUrl = await photoReference
          .getDownloadURL()
          .timeout(const Duration(seconds: 15));
      final ownerName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'Miembro de la manada';
      onProgress?.call('GUARDANDO PUBLICACIÓN…');
      postWriteStarted = true;
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
      }).timeout(const Duration(seconds: 30));
    } catch (error, stackTrace) {
      debugPrint('No se pudo publicar en el muro: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!(postWriteStarted && error is TimeoutException)) {
        try {
          await photoReference.delete().timeout(const Duration(seconds: 10));
        } on FirebaseException catch (cleanupError, cleanupStackTrace) {
          if (cleanupError.code != 'object-not-found' &&
              cleanupError.code != 'unauthorized') {
            debugPrint(
              'No se pudo limpiar la foto de la publicación: '
              '${cleanupError.code}',
            );
            debugPrintStack(stackTrace: cleanupStackTrace);
          }
        } on TimeoutException catch (cleanupError, cleanupStackTrace) {
          debugPrint('La limpieza de la foto excedió el tiempo límite.');
          debugPrintStack(
            stackTrace: cleanupStackTrace,
            label: cleanupError.message,
          );
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint('No se pudo limpiar la foto: $cleanupError');
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
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
