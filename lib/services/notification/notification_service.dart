import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firestore_service.dart';

/// Top-level handler for background/terminated push messages.
/// Must be a top-level function (not a class method) per Firebase requirements.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background message received — no metadata logged for privacy.
}

/// Push notification service.
/// Registers FCM token and handles incoming notification taps.
class NotificationService {
  final FirebaseMessaging _messaging;
  final FirestoreService _firestore;

  NotificationService({
    FirebaseMessaging? messaging,
    required FirestoreService firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore;

  Future<void> initialize(String userId) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await _messaging.getToken();
        if (token != null) {
          await _firestore.registerFcmToken(userId: userId, token: token);
        }

        _messaging.onTokenRefresh.listen((newToken) {
          _firestore.registerFcmToken(userId: userId, token: newToken);
        });
      }

      FirebaseMessaging.onMessage.listen((_) {
        // Foreground push received — no metadata logged.
      });

      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        // Notification tap — no metadata logged.
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Notification init failed');
    }
  }
}
