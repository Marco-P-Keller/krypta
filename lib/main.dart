import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'features/calculator/logic/code_detector.dart';
import 'features/messenger/logic/messenger_provider.dart';
import 'security/device/device_integrity_policy.dart';
import 'security/encryption/encryption_service.dart';
import 'security/hardware/hardware_security_binding.dart';
import 'security/key_management/key_manager.dart';
import 'security/prekey/prekey_manager.dart';
import 'services/emergency/emergency_wipe_service.dart';
import 'services/firebase/auth_service.dart';
import 'services/firebase/firestore_service.dart';
import 'services/notification/notification_service.dart';
import 'services/platform/platform_security_service.dart';
import 'security/transparency/key_commitment.dart';
import 'security/transparency/key_transparency_log.dart';
import 'security/transparency/consistency_checker.dart';
import 'core/locale/locale_controller.dart';
import 'services/storage/encrypted_local_store.dart';
import 'services/storage/file_helper.dart' as file_helper;
import 'services/storage/secure_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Certificate pinning is enforced natively:
  //   - Android: android/app/src/main/res/xml/network_security_config.xml
  //   - iOS:     ios/Runner/Info.plist (NSPinnedDomains)
  // All Firebase SDK traffic flows through the platform HTTP stack, so the
  // native layer covers every network request this app makes. No dart:io
  // HttpClient consumers exist; a Dart-level HttpOverrides shim was removed
  // because it could not actually validate SPKIs from badCertificateCallback.

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

  // H3: recover from an interrupted emergency wipe. If the marker is set,
  // a previous wipe did not fully complete — delete any leftover identity
  // keys AND secure-storage entries. Only clear the marker if we can
  // verify identity keys are gone; otherwise leave it so the next startup
  // tries again. Mirrors the end-of-wipe check in EmergencyWipeService.
  try {
    if (await file_helper.isWipeMarkerSet()) {
      if (kDebugMode) {
        debugPrint('Interrupted wipe detected — forcing clean state');
      }
      try {
        await keyManager.deleteAllKeys();
      } catch (_) {}
      try {
        await secureStorage.deleteAll();
      } catch (_) {}
      try {
        await localStore.wipeAll();
      } catch (_) {}
      try {
        if (!await keyManager.hasIdentityKeys()) {
          await file_helper.clearWipeMarker();
        } else if (kDebugMode) {
          debugPrint('Recovery wipe incomplete — marker retained');
        }
      } catch (_) {
        // Verification failed — leave marker set (fail-safe).
      }
    }
  } catch (_) {}
  final platformSecurity = PlatformSecurityService();
  final deviceIntegrity = DeviceIntegrityPolicyService(
    platform: platformSecurity,
  );
  final notificationService = NotificationService(firestore: firestoreService);

  // Hardware security: detect capabilities and prepare wrapping key.
  // Must run after device integrity check so we know if hardware is trustworthy.
  final hardwareBinding = HardwareSecurityBinding(integrity: deviceIntegrity);
  await deviceIntegrity.checkIntegrity();
  await hardwareBinding.initialize();

  // If hardware binding is available, create the wrapping key and attach
  // it to the local store BEFORE init (so init can unwrap/wrap keys).
  if (hardwareBinding.isHardwareBindingAvailable) {
    await hardwareBinding.createHardwareKey();
  }
  localStore.setHardwareBinding(hardwareBinding);

  // Key Transparency: hash-chained commitment log for MITM detection.
  // Must be set up before KeyManager so key creation publishes commitments.
  final transparencyLog = KeyTransparencyLog(store: localStore);
  final consistencyChecker = ConsistencyChecker(log: transparencyLog);
  keyManager.setTransparency(
    log: transparencyLog,
    onCommitmentCreated: (KeyCommitment commitment) async {
      final userId = await secureStorage.getUserId();
      if (userId != null) {
        await firestoreService.publishKeyCommitment(
          userId: userId,
          commitment: commitment.toMap(),
          epoch: commitment.epoch,
        );
      }
    },
  );

  final preKeyManager = PreKeyManager(localStore: localStore);

  final emergencyWipeService = EmergencyWipeService(
    secureStorage: secureStorage,
    keyManager: keyManager,
    localStore: localStore,
    firestore: firestoreService,
    preKeyManager: preKeyManager,
  );

  final messengerProvider = MessengerProvider(
    encryption: encryptionService,
    keyManager: keyManager,
    auth: authService,
    firestore: firestoreService,
    localStore: localStore,
    notifications: notificationService,
    secureStorage: secureStorage,
    preKeyManager: preKeyManager,
  );
  messengerProvider.setTransparency(
    log: transparencyLog,
    checker: consistencyChecker,
  );

  // Die Sprachwahl vor dem ersten Bild laden, sonst blitzt kurz die
  // falsche Sprache auf.
  final localeController = LocaleController(
    read: secureStorage.getLanguageCode,
    write: secureStorage.setLanguageCode,
  );
  await localeController.load();

  runApp(
    MultiProvider(
      providers: [
        Provider<SecureStorageService>.value(value: secureStorage),
        ChangeNotifierProvider<LocaleController>.value(value: localeController),
        Provider<EncryptionService>.value(value: encryptionService),
        Provider<KeyManager>.value(value: keyManager),
        Provider<AuthService>.value(value: authService),
        Provider<FirestoreService>.value(value: firestoreService),
        Provider<CodeDetector>.value(value: codeDetector),
        Provider<EncryptedLocalStore>.value(value: localStore),
        Provider<PlatformSecurityService>.value(value: platformSecurity),
        Provider<DeviceIntegrityPolicyService>.value(value: deviceIntegrity),
        Provider<HardwareSecurityBinding>.value(value: hardwareBinding),
        Provider<KeyTransparencyLog>.value(value: transparencyLog),
        Provider<ConsistencyChecker>.value(value: consistencyChecker),
        Provider<NotificationService>.value(value: notificationService),
        Provider<EmergencyWipeService>.value(value: emergencyWipeService),
        ChangeNotifierProvider<MessengerProvider>.value(value: messengerProvider),
      ],
      child: const KryptaApp(),
    ),
  );
}
