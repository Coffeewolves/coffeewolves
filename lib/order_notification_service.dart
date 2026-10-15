import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class OrderNotificationService {
  OrderNotificationService(this._firestore);

  static const _webVapidKey = String.fromEnvironment('WOLVES_FCM_VAPID_KEY');

  final FirebaseFirestore _firestore;
  bool get isWebPushConfigured => _webVapidKey.isNotEmpty;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  String? _registeredUid;

  Future<void> activateForAuthorizedUser(
    String uid, {
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    if (!kIsWeb) {
      throw StateError(
          'Las notificaciones push solo están configuradas para web.');
    }
    if (!isWebPushConfigured) {
      throw StateError(
        'Falta WOLVES_FCM_VAPID_KEY. Configura la clave pública Web Push '
        'de Firebase y vuelve a compilar la app.',
      );
    }
    final messaging = FirebaseMessaging.instance;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid || user.isAnonymous) {
      throw StateError(
        'Inicia sesión con tu cuenta verificada de Gerencia o personal.',
      );
    }

    // Start the permission prompt before awaiting anything so browsers still
    // consider this call to come from the user's button tap.
    final permissionFuture = messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (!await messaging.isSupported()) {
      await permissionFuture;
      throw StateError(
        'Este navegador no admite notificaciones push web. '
        'Prueba Chrome o instala la app como PWA.',
      );
    }
    final permission = await permissionFuture;
    if (permission.authorizationStatus != AuthorizationStatus.authorized) {
      throw StateError(
        'Permite las notificaciones de Coffee Wolves en la configuración '
        'del navegador y del dispositivo.',
      );
    }

    final token = await messaging.getToken(vapidKey: _webVapidKey);
    if (token == null || token.isEmpty) {
      throw StateError(
        'Firebase no entregó un token push. Revisa VAPID y el service worker.',
      );
    }
    await _saveStaffToken(uid, token);
    _registeredUid = uid;
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = null;
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
      (refreshedToken) {
        if (_registeredUid != uid ||
            FirebaseAuth.instance.currentUser?.uid != uid) {
          return;
        }
        unawaited(_saveStaffToken(uid, refreshedToken).catchError(
          (Object error, StackTrace stackTrace) {
            debugPrint('No se pudo actualizar el registro push: $error');
            debugPrintStack(stackTrace: stackTrace);
          },
        ));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Falló la renovación del token push: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    if (onForegroundMessage != null) {
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        onForegroundMessage,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Falló la notificación push en primer plano: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
    }
  }

  Future<void> _saveStaffToken(String uid, String token) async {
    final digest = sha256.convert(token.codeUnits).toString();
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('pushTokens')
        .doc(digest)
        .set({
      'token': token,
      'platform': 'web',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> dispose() async {
    _registeredUid = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = null;
  }
}
