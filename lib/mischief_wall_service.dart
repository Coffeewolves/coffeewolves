import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

class MischiefWallService {
  static const maxImageBytes = 200 * 1024;
  static const maxVideoBytes = 5 * 1024 * 1024;
  static const videoChunkBytes = 450 * 1024;

  static String videoContentTypeForFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => throw const FormatException(
          'Elige un video MP4, MOV o WebM.',
        ),
    };
  }

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
    required Uint8List mediaBytes,
    required String mediaType,
    required String mediaContentType,
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
    final maxMediaBytes = mediaType == 'video' ? maxVideoBytes : maxImageBytes;
    if (mediaType != 'image' && mediaType != 'video') {
      throw ArgumentError.value(mediaType, 'mediaType', 'Formato no válido.');
    }
    if (mediaBytes.isEmpty || mediaBytes.length > maxMediaBytes) {
      throw ArgumentError.value(
        mediaBytes.length,
        'mediaBytes',
        mediaType == 'video'
            ? 'El video debe pesar como máximo 5 MB.'
            : 'La imagen debe pesar como máximo 200 KB.',
      );
    }
    if (mediaType == 'video' &&
        !const {'video/mp4', 'video/quicktime', 'video/webm'}
            .contains(mediaContentType)) {
      throw ArgumentError.value(
        mediaContentType,
        'mediaContentType',
        'Usa un video MP4, MOV o WebM.',
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
      onProgress?.call('GUARDANDO EN FIRESTORE…');
      await _firestore.runTransaction<void>((transaction) async {
        final statsSnapshot = await transaction.get(_communityStats);
        final stats = statsSnapshot.data() ?? const <String, dynamic>{};
        final storedMemberCount = stats['memberCount'];
        if (statsSnapshot.exists && storedMemberCount is! int) {
          throw StateError('El contador de miembros no es válido.');
        }
        final memberCount = statsSnapshot.exists ? storedMemberCount as int : 1;
        final storedDailyPostCount = stats['dailyPostCount'];
        if (statsSnapshot.exists && storedDailyPostCount is! int) {
          throw StateError('El contador diario de publicaciones no es válido.');
        }
        final priorPostsToday = stats['dailyPostDate'] == today
            ? statsSnapshot.exists
                ? storedDailyPostCount as int
                : 0
            : 0;
        if (memberCount < 0 || priorPostsToday < 0) {
          throw StateError('Los contadores del Muro no son válidos.');
        }
        final dailyPostCount = priorPostsToday + 1;
        final retention = mischiefPostLifetime(
          memberCount: memberCount,
          postsToday: dailyPostCount,
        );

        final postData = <String, dynamic>{
          'ownerUid': user.uid,
          'ownerName':
              ownerName.length > 80 ? ownerName.substring(0, 80) : ownerName,
          'dogName': dogName.trim(),
          'description': description.trim(),
          'mediaType': mediaType,
          'mediaContentType': mediaContentType,
          'fecha_Expiracion': Timestamp.fromDate(now.add(retention)),
          'innocentVotes': 0,
          'guiltyVotes': 0,
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (mediaType == 'image') {
          postData['photoBase64'] = base64Encode(mediaBytes);
        } else {
          final chunkCount = (mediaBytes.length / videoChunkBytes).ceil();
          postData['videoChunkCount'] = chunkCount;
          for (var index = 0; index < chunkCount; index++) {
            final start = index * videoChunkBytes;
            final end = (start + videoChunkBytes).clamp(0, mediaBytes.length);
            transaction.set(
              post
                  .collection('videoChunks')
                  .doc(index.toString().padLeft(3, '0')),
              {
                'index': index,
                'ownerUid': user.uid,
                'dataBase64': base64Encode(mediaBytes.sublist(start, end)),
              },
            );
          }
        }
        transaction.set(post, postData);
        final statsUpdate = {
          'dailyPostDate': today,
          'dailyPostCount': dailyPostCount,
          'lastPostId': post.id,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (statsSnapshot.exists) {
          transaction.update(_communityStats, statsUpdate);
        } else {
          transaction.set(_communityStats, {
            'memberCount': 1,
            'dailyPostDate': today,
            'dailyPostCount': dailyPostCount,
            'lastMemberUid': '',
            'lastPostId': post.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
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

  Future<Uint8List> getVideoBytes(
    String postId, {
    required int chunkCount,
  }) async {
    if (chunkCount < 1 || chunkCount > 12) {
      throw StateError('El video publicado tiene un formato no válido.');
    }
    final chunks = await _posts
        .doc(postId)
        .collection('videoChunks')
        .orderBy('index')
        .get();
    if (chunks.docs.length != chunkCount) {
      throw StateError(
          'No se pudieron recuperar todos los fragmentos del video.');
    }
    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < chunks.docs.length; index++) {
      final chunk = chunks.docs[index].data();
      if (chunk['index'] != index || chunk['dataBase64'] is! String) {
        throw StateError('Uno de los fragmentos del video no es válido.');
      }
      builder.add(base64Decode(chunk['dataBase64'] as String));
    }
    return builder.takeBytes();
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

Duration mischiefPostLifetime({
  required int memberCount,
  required int postsToday,
}) {
  if (postsToday >= 1000) return const Duration(days: 1);
  if (memberCount >= 5000) return const Duration(days: 3);
  return const Duration(days: 7);
}
