import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'features/calculator/logic/code_detector.dart';
import 'features/decoy/decoy_provider.dart';
import 'features/messenger/logic/messenger_provider.dart';
import 'security/encryption/encryption_service.dart';
import 'security/key_management/key_manager.dart';
import 'services/emergency/emergency_wipe_service.dart';
import 'services/firebase/auth_service.dart';
import 'services/firebase/firestore_service.dart';
import 'services/notification/notification_service.dart';
import 'services/platform/platform_security_service.dart';
import 'services/storage/encrypted_local_store.dart';
import 'services/storage/secure_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final secureStorage = SecureStorageService();
  final encryptionService = EncryptionService();
  final keyManager = KeyManager(encryption: encryptionService);
  final authService = AuthService();
  final firestoreService = FirestoreService();
  final codeDetector = CodeDetector(storage: secureStorage);
  final localStore = EncryptedLocalStore(encryption: encryptionService);
  final platformSecurity = PlatformSecurityService();
  final notificationService = NotificationService(firestore: firestoreService);

  final emergencyWipeService = EmergencyWipeService(
    secureStorage: secureStorage,
    keyManager: keyManager,
    localStore: localStore,
    firestore: firestoreService,
  );

  final decoyProvider = DecoyProvider(store: localStore);

  final messengerProvider = MessengerProvider(
    encryption: encryptionService,
    keyManager: keyManager,
    auth: authService,
    firestore: firestoreService,
    localStore: localStore,
    notifications: notificationService,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<SecureStorageService>.value(value: secureStorage),
        Provider<EncryptionService>.value(value: encryptionService),
        Provider<KeyManager>.value(value: keyManager),
        Provider<AuthService>.value(value: authService),
        Provider<FirestoreService>.value(value: firestoreService),
        Provider<CodeDetector>.value(value: codeDetector),
        Provider<EncryptedLocalStore>.value(value: localStore),
        Provider<PlatformSecurityService>.value(value: platformSecurity),
        Provider<NotificationService>.value(value: notificationService),
        Provider<EmergencyWipeService>.value(value: emergencyWipeService),
        ChangeNotifierProvider<DecoyProvider>.value(value: decoyProvider),
        ChangeNotifierProvider<MessengerProvider>.value(value: messengerProvider),
      ],
      child: const KryptaApp(),
    ),
  );
}
