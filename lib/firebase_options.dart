// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAMGoDDDNGcDu2iyXrWqhijLFKTzPo58Pw',
    appId: '1:583308772620:web:ac651ab0d6c2c55adf3529',
    messagingSenderId: '583308772620',
    projectId: 'sapori-di-mare',
    authDomain: 'sapori-di-mare.firebaseapp.com',
    databaseURL: 'https://sapori-di-mare-default-rtdb.firebaseio.com',
    storageBucket: 'sapori-di-mare.firebasestorage.app',
    measurementId: 'G-MHJNTKGY38',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'LA-TUA-API-KEY-ANDROID',
    appId: '1:583308772620:android:IL-TUO-APP-ID',
    messagingSenderId: '583308772620',
    projectId: 'sapori-di-mare',
    databaseURL: 'https://sapori-di-mare-default-rtdb.firebaseio.com',
    storageBucket: 'sapori-di-mare.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'LA-TUA-API-KEY-IOS',
    appId: '1:583308772620:ios:IL-TUO-APP-ID',
    messagingSenderId: '583308772620',
    projectId: 'sapori-di-mare',
    databaseURL: 'https://sapori-di-mare-default-rtdb.firebaseio.com',
    storageBucket: 'sapori-di-mare.firebasestorage.app',
    iosBundleId: 'com.example.projectNewPulito',
  );
}