import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firestore_service.dart';

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
      // Request permission (iOS)
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

        // Listen for token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          _firestore.registerFcmToken(userId: userId, token: newToken);
        });
      }

      // Handle foreground messages (content-free, just triggers sync)
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('FCM foreground: ${message.messageId}');
      });
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }
}
