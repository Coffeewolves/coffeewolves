import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class MischiefWallService {
  MischiefWallService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('mischiefPosts');
  DocumentReference<Map<String, dynamic>> get _communityStats =>
      _firestore.collection('communityStats').doc('mischiefWall');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() {
    return _posts
        .where(
          'fecha_Expiracion',
          isGreaterThan: Timestamp.fromDate(DateTime.now().toUtc()),
        )
        .orderBy('fecha_Expiracion')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
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
    try {
      onProgress?.call('PREPARANDO PUBLICACIÓN…');
      final ownerName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'Miembro de la manada';
      final now = DateTime.now().toUtc();
      final today = _utcDateKey(now);
      onProgress?.call('GUARDANDO FOTO…');
      await _firestore.runTransaction<void>((transaction) async {
        final statsSnapshot = await transaction.get(_communityStats);
        final stats = statsSnapshot.data();
        if (!statsSnapshot.exists || stats == null) {
          throw StateError(
            'El contador del Muro todavía no está inicializado. '
            'Gerencia debe ejecutar el script local de mantenimiento.',
          );
        }
        final memberCount = stats['memberCount'];
        final priorPostsToday = stats['dailyPostDate'] == today
            ? stats['dailyPostCount'] as int? ?? 0
            : 0;
        if (memberCount is! int || memberCount < 0 || priorPostsToday < 0) {
          throw StateError(
            'Los contadores del Muro no son válidos. '
            'Ejecuta el script local de mantenimiento.',
          );
        }
        final dailyPostCount = priorPostsToday + 1;
        final retention = mischiefPostLifetime(
          memberCount: memberCount,
          postsToday: dailyPostCount,
        );

        transaction.set(post, {
          'ownerUid': user.uid,
          'ownerName':
              ownerName.length > 80 ? ownerName.substring(0, 80) : ownerName,
          'dogName': dogName.trim(),
          'description': description.trim(),
          'photoBase64': base64Encode(imageBytes),
          'fecha_Expiracion': Timestamp.fromDate(now.add(retention)),
          'innocentVotes': 0,
          'guiltyVotes': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(_communityStats, {
          'dailyPostDate': today,
          'dailyPostCount': dailyPostCount,
          'lastPostId': post.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 30));
    } catch (error, stackTrace) {
      debugPrint('No se pudo publicar en el muro: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  static String _utcDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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

Duration mischiefPostLifetime({
  required int memberCount,
  required int postsToday,
}) {
  if (postsToday >= 1000) return const Duration(days: 1);
  if (memberCount >= 5000) return const Duration(days: 3);
  return const Duration(days: 7);
}
