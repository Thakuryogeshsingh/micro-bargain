import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../location/location_service.dart';
import '../network/api_client.dart';

/// Push notifications through Firebase. Until android/app/google-services.json is added,
/// Firebase cannot start: the app then works normally and notifications appear in the in-app inbox only.
class PushService {
  static bool _ready = false;
  static String? token;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Call after login and on each app start: sends the FCM token and current location to the server.
  static Future<void> register(ApiClient api, {void Function(RemoteMessage)? onForegroundMessage}) async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      // getToken/onTokenRefresh are deprecated in favour of a newer registration API but still work.
      // ignore: deprecated_member_use
      token = await messaging.getToken();
      if (token == null) return;
      final here = await currentLocation();
      await api.post('/notifications/devices/', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        if (!here.isFallback) 'latitude': here.latitude,
        if (!here.isFallback) 'longitude': here.longitude,
      });
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((fresh) {
        token = fresh;
        api.post('/notifications/devices/', {'token': fresh});
      });
      if (onForegroundMessage != null) FirebaseMessaging.onMessage.listen(onForegroundMessage);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }
}
