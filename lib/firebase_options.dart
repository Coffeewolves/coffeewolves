import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Firebase solo está configurado para Flutter Web. '
          'Registra y configura Firebase para esta plataforma.',
        );
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase no está configurado para Fuchsia.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCXs0XqqOS0WJwvZwMreagmG8UWZM1Anqg',
    appId: '1:639914979018:web:fbcf5b96118deefc308e33',
    messagingSenderId: '639914979018',
    projectId: 'wolves-club-fb24a',
    authDomain: 'wolves-club-fb24a.firebaseapp.com',
    storageBucket: 'wolves-club-fb24a.firebasestorage.app',
    measurementId: 'G-P86KN35DB4',
  );
}
