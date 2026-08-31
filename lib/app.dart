import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'core/locale/locale_controller.dart';
import 'features/auth/presentation/welcome_back_screen.dart';
import 'features/settings/presentation/language_screen.dart';
import 'features/messenger/logic/key_publish_status.dart';
import 'features/auth/presentation/setup_screen.dart';
import 'features/auth/presentation/tutorial_screen.dart';
import 'features/auth/presentation/vault_password_screen.dart';
import 'features/calculator/presentation/calculator_screen.dart';
import 'features/messenger/data/models/chat_model.dart';
import 'features/messenger/logic/messenger_provider.dart';
import 'features/messenger/logic/sync_lifecycle_policy.dart';
import 'features/messenger/presentation/chat_list_screen.dart';
import 'features/messenger/presentation/chat_screen.dart';
import 'features/messenger/presentation/new_chat_screen.dart';
import 'features/messenger/presentation/qr_scanner_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'security/device/device_integrity_policy.dart';
import 'services/emergency/emergency_wipe_service.dart';
import 'services/platform/clipboard_helper.dart';
import 'services/platform/biometric_outcome.dart';
import 'services/platform/platform_security_service.dart';
import 'services/platform/privacy_cover.dart';
import 'services/storage/encrypted_local_store.dart';
import 'services/storage/secure_storage_service.dart';
import 'services/storage/legacy_cleanup.dart';
import 'theme/app_theme.dart';

class KryptaApp extends StatelessWidget {
  const KryptaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Die Liste kommt aus dem Controller, damit sie nicht an zwei Stellen
      // gepflegt werden muss und nicht auseinanderlaufen kann.
      supportedLocales: LocaleController.supported,
      // Die bewusste Wahl des Nutzers schlaegt die Geraetesprache. Ohne das
      // hier richtete sich die App nach dem Telefon — und weil ein guter Teil
      // der Oberflaeche fest verdrahtete Texte trug, ergab das einen
      // Mischmasch aus Deutsch und Englisch.
      locale: context.watch<LocaleController>().locale,
      home: const KryptaShell(),
    );
  }
}

/// Root navigation shell.
///
/// Navigation is state-based (no named routes / deep links).
/// This prevents app structure from leaking into system logs.
class KryptaShell extends StatefulWidget {
  const KryptaShell({super.key});

  @override
  State<KryptaShell> createState() => _KryptaShellState();
}

enum _AppScreen {
  calculator,
  // Steht vor dem Tutorial: alles danach ist Text, und der soll in der
  // Sprache erscheinen, die der Nutzer versteht.
  language,
  setup,
  tutorial,
  /// Übergang zwischen Taschenrechner und Messenger — begrüßt und lädt.
  welcomeBack,
  vaultPassword,
  messenger,
  chat,
  newChat,
  qrScanner,
  settings,
}

class _KryptaShellState extends State<KryptaShell> with WidgetsBindingObserver {
  _AppScreen _currentScreen = _AppScreen.calculator;
  bool _isInitialized = false;

  /// Nimmt die Abdeckung des App-Umschalters erst ab, wenn ein Bild steht.
  late final PrivacyCover _privacyCover =
      PrivacyCover(context.read<PlatformSecurityService>());

  DeviceIntegrityAction _deviceAction = DeviceIntegrityAction.allow;
  Chat? _selectedChat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    // C6: ensure periodic integrity polling doesn't outlive the shell.
    try {
      context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When app goes to background, always lock back to calculator.
  /// This ensures the messenger is never visible when returning to the app.
  ///
  /// Only `paused` / `hidden` triggers the lock — `inactive` fires for
  /// transient interruptions (screenshot, permission prompt, control-center
  /// peek, incoming call overlay) which should NOT count as backgrounding.
  /// Die Vorschau im App-Umschalter deckt ein eigener Mechanismus ab, der
  /// unabhaengig vom Screenshot-Hinweis laeuft.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Der Empfang zuerst, vor allem anderen. Er hing bisher an gar nichts:
    // im Hintergrund lief der Listener gegen eine gekappte Verbindung
    // weiter, und beim Aufwachen holte ihn niemand zurueck — eine
    // Kontaktanfrage vom Vormittag lag deshalb nach dem Oeffnen noch eine
    // Minute herum, obwohl die Chatliste laengst stand.
    final messenger = context.read<MessengerProvider>();
    if (SyncLifecyclePolicy.shouldPause(state)) {
      messenger.pauseSync();
    } else if (SyncLifecyclePolicy.shouldResume(state)) {
      messenger.resumeSync();
    }

    final isBackgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (isBackgrounded) {
      // Evict stale ratchet state entries (containing private keys) from memory.
      // This reduces the window where sensitive cryptographic material is in RAM.
      context.read<EncryptedLocalStore>().evictStaleCacheEntries();
      // C6: stop periodic integrity polling while backgrounded — the resume
      // path re-runs a one-shot check and _unlockMessenger re-starts it.
      context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
      // M2-Client (audit 2026-05 follow-up): the 60s clipboard auto-clear
      // timer dies if the OS kills the backgrounded app, so wipe now while
      // we still hold the process. No-op if the user has since copied
      // something else themselves.
      unawaited(ClipboardHelper.clearEphemeralNow());

      // Die Einrichtung ist ausgenommen: wer beim ersten Start kurz die App
      // verlässt, soll nicht auf dem Rechner landen, ohne je einen Code
      // vergeben zu haben. Der Willkommens-Übergang ist NICHT ausgenommen —
      // dahinter liegt bereits der entsperrte Messenger.
      if (_currentScreen != _AppScreen.calculator &&
          _currentScreen != _AppScreen.setup &&
          _currentScreen != _AppScreen.language &&
          _currentScreen != _AppScreen.tutorial) {
        // Do NOT disable screenshot protection here — keep it active
        // until the calculator screen is fully visible.
        if (mounted) {
          setState(() {
            _currentScreen = _AppScreen.calculator;
            _selectedChat = null;
          });
          // Disable screenshot protection AFTER state change, so the
          // calculator is rendered before the secure flag is removed.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final platform = context.read<PlatformSecurityService>();
              platform.disableScreenshotProtection();
            }
          });
        }
      }
    }

    // On resume, re-validate device integrity and evict stale cache entries.
    if (state == AppLifecycleState.resumed) {
      final integrity = context.read<DeviceIntegrityPolicyService>();
      final store = context.read<EncryptedLocalStore>();

      // Die Abdeckung faellt erst, wenn ein Bild steht — und die Pruefungen
      // laufen erst danach. Beide gehoeren zusammen: `recheck` tastet das
      // Dateisystem synchron ab (vierzehn Pfade und ein Schreibversuch, den
      // die Sandbox ablehnt) und blockiert dabei genau den Faden, der das
      // Bild bauen soll. Frueher stand das vor dem ersten Bild und die
      // Abdeckung fiel nach Zeit — wer beides verlor, sah den Messenger
      // aufblitzen.
      _privacyCover.dismissWhenPainted(afterwards: () {
        if (!mounted) return;
        integrity.recheck().then((_) {
          if (!mounted) return;
          final action = integrity.enforce();
          if (action != _deviceAction) {
            setState(() => _deviceAction = action);
          }
        });
        store.evictStaleCacheEntries();
      });
    }
  }

  Future<void> _initialize() async {
    // Capture context references before async gaps.
    final integrity = context.read<DeviceIntegrityPolicyService>();
    final storage = context.read<SecureStorageService>();
    final store = context.read<EncryptedLocalStore>();

    // Device integrity check — enforce configured policy.
    await integrity.checkIntegrity();
    final action = integrity.enforce();
    if (!mounted) return;

    if (action == DeviceIntegrityAction.block) {
      setState(() {
        _deviceAction = action;
        _isInitialized = true;
      });
      return;
    }

    // Store the action for UI (warning banners etc.)
    _deviceAction = action;

    final isSetup = await storage.isSetupComplete();

    if (!isSetup) {
      if (!mounted) return;
      setState(() {
        // Beim allerersten Start zuerst die Sprache. Wurde sie schon einmal
        // gewaehlt (etwa nach einem abgebrochenen Einrichten), direkt weiter
        // ins Tutorial.
        _currentScreen = context.read<LocaleController>().hasChosen
            ? _AppScreen.tutorial
            : _AppScreen.language;
        _isInitialized = true;
      });
      return;
    }

    // Einmalig die Reste des ausgebauten Tarn-Messengers wegraeumen. Nur
    // eingerichtete Installationen koennen welche haben — ein frisches Geraet
    // hat den Modus nie gesehen. Scheitert der Lauf, bleibt der Merker aus
    // und der naechste Start holt es nach.
    await LegacyCleanup(
      markerSet: storage.isLegacyCleanupDone,
      setMarker: storage.markLegacyCleanupDone,
      purgeFiles: store.purgeLegacyDecoyFiles,
      deleteLegacyKeys: storage.deleteLegacyKeys,
    ).run();

    if (!mounted) return;
    setState(() {
      _currentScreen = _AppScreen.calculator;
      _isInitialized = true;
    });
  }

  Future<void> _onSecretCode() async {
    // Defense-in-depth: block messenger access on compromised devices.
    if (_deviceAction == DeviceIntegrityAction.block) return;

    final storage = context.read<SecureStorageService>();
    final platform = context.read<PlatformSecurityService>();
    // Vor dem ersten await gelesen: danach ist der context nicht mehr
    // unstrittig gueltig, und der Text wird erst nach mehreren awaits
    // gebraucht.
    final l10n = AppLocalizations.of(context)!;

    // H4: if the unified fail counter is already at wipe threshold, act now.
    // This catches the case where an earlier biometric-only session
    // accumulated enough fails to wipe.
    if (await storage.getVaultFailCount() >=
        SecureStorageService.maxVaultAttempts) {
      await _handleEmergencyWipe();
      return;
    }

    final biometricEnabled = await storage.isBiometricEnabled();

    if (biometricEnabled) {
      final outcome = await platform.authenticateDetailed(
        reason: l10n.biometricUnlockReason,
      );
      if (!mounted) return;
      if (outcome != BiometricOutcome.success) {
        // H4: unify biometric fails into the vault counter so an attacker
        // cannot burn through biometric attempts and then get a fresh
        // 5-attempt vault budget.
        //
        // Aber nur eine echte Ablehnung zaehlt. Ein Abbruch oder ein Geraet,
        // das gerade nicht pruefen kann, ist kein Angriffsversuch — und
        // fuenf davon wuerden alles loeschen. Zugang gibt es trotzdem
        // keinen: ohne Erfolg geht es hier nicht weiter.
        if (outcome.countsAsFailedAttempt) {
          await storage.incrementVaultFailCount();
          final fails = await storage.getVaultFailCount();
          if (fails >= SecureStorageService.maxVaultAttempts) {
            await _handleEmergencyWipe();
          }
        }
        return;
      }
      // Biometric success — reset counter so one bad taps don't linger.
      await storage.resetVaultFailCount();
    }

    final vaultEnabled = await storage.isVaultPasswordEnabled();
    if (!mounted) return;
    if (vaultEnabled) {
      setState(() => _currentScreen = _AppScreen.vaultPassword);
      return;
    }

    await _unlockMessenger();
  }

  /// Wie lange der Willkommensbildschirm mindestens steht.
  ///
  /// Ohne Untergrenze blitzt er auf einem schnellen Gerät nur auf, was
  /// unruhiger wirkt als gar kein Übergang. Dauert das Laden länger, bleibt
  /// er entsprechend länger stehen — er ist auch der Ladebildschirm.
  static const _welcomeBackMinimum = Duration(milliseconds: 900);

  Future<void> _unlockMessenger() async {
    final platform = context.read<PlatformSecurityService>();
    final messenger = context.read<MessengerProvider>();
    final integrity = context.read<DeviceIntegrityPolicyService>();

    // Erst der Übergang, dann die Arbeit: Schlüssel laden und den
    // Aufnahmeschutz einrichten dauert, und solange soll nicht der Rechner
    // stehenbleiben, als wäre der Code nicht angekommen.
    if (mounted) setState(() => _currentScreen = _AppScreen.welcomeBack);
    final gezeigtSeit = DateTime.now();

    // Enable screenshot/recording protection BEFORE rendering the messenger.
    // Awaited so the native content mask is installed first. If the OS mask
    // is unavailable (returns false), we continue in a degraded mode rather
    // than blocking the messenger — E2E encryption is the core guarantee and
    // the post-capture warning stays honest about the unprotected state.
    await platform.enableScreenshotProtection();
    await messenger.initialize();

    // C6: start periodic integrity monitoring while the messenger is unlocked
    // — catches Frida / debugger attachment that happens after the initial
    // start-time check. Stopped on background/logout/emergency wipe.
    integrity.startPeriodicChecks(
      onAction: (action) {
        if (!mounted) return;
        if (action != _deviceAction) {
          setState(() => _deviceAction = action);
        }
      },
    );

    // Den Rest der Mindestdauer abwarten, falls das Laden schneller war.
    final verstrichen = DateTime.now().difference(gezeigtSeit);
    if (verstrichen < _welcomeBackMinimum) {
      await Future<void>.delayed(_welcomeBackMinimum - verstrichen);
    }

    if (mounted) setState(() => _currentScreen = _AppScreen.messenger);
  }

  Future<void> _handleEmergencyWipe() async {
    final wipeService = context.read<EmergencyWipeService>();
    final messenger = context.read<MessengerProvider>();
    final platform = context.read<PlatformSecurityService>();
    final integrity = context.read<DeviceIntegrityPolicyService>();

    integrity.stopPeriodicChecks();
    await messenger.wipeAll();
    await wipeService.wipeEverything();
    await platform.disableScreenshotProtection();

    if (mounted) {
      setState(() {
        _currentScreen = _AppScreen.setup;
        _selectedChat = null;
      });
    }
  }

  void _backToCalculator() {
    // C6: stop periodic integrity checks — messenger is no longer active.
    context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();
    setState(() => _currentScreen = _AppScreen.calculator);
    // Disable screenshot protection AFTER calculator is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final platform = context.read<PlatformSecurityService>();
        platform.disableScreenshotProtection();
      }
    });
  }

  void _navigateTo(_AppScreen screen) => setState(() => _currentScreen = screen);

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Hard block on compromised devices — shows blank calculator-like screen.
    // Only triggered when policy is [DeviceIntegrityPolicy.block].
    if (_deviceAction == DeviceIntegrityAction.block) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Calculator',
            style: TextStyle(fontSize: 20, color: Colors.grey),
          ),
        ),
      );
    }

    final screen = _buildCurrentScreen();

    // Wrap messenger screens with integrity warning if device is compromised.
    final showWarning = _deviceAction == DeviceIntegrityAction.warnAndDegrade ||
        _deviceAction == DeviceIntegrityAction.warnOnly;
    final isMessengerScreen = _currentScreen == _AppScreen.messenger ||
        _currentScreen == _AppScreen.chat ||
        _currentScreen == _AppScreen.newChat ||
        _currentScreen == _AppScreen.qrScanner ||
        _currentScreen == _AppScreen.settings;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: isMessengerScreen
          ? _wrapWithBanners(screen, integrity: showWarning)
          : screen,
    );
  }

  /// Legt die Warnbanner über einen Messenger-Bildschirm.
  ///
  /// Der Schlüssel-Zustand wird per [Selector] gelesen statt per `watch`:
  /// sonst würde die ganze Hülle bei jeder Änderung im MessengerProvider neu
  /// bauen — also bei jeder eingehenden Nachricht.
  Widget _wrapWithBanners(Widget screen, {required bool integrity}) {
    return Column(
      key: ValueKey('shell_${screen.key}'),
      children: [
        if (integrity) _buildIntegrityBanner(context),
        Selector<MessengerProvider, KeyPublishState>(
          selector: (_, messenger) => messenger.keyPublishState,
          builder: (context, state, _) => state == KeyPublishState.ok
              ? const SizedBox.shrink()
              : _buildKeyPublishBanner(context, state),
        ),
        Expanded(child: screen),
      ],
    );
  }

  /// Persistent device integrity warning banner.
  Widget _buildIntegrityBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final degraded = _deviceAction == DeviceIntegrityAction.warnAndDegrade;
    return MaterialBanner(
      backgroundColor: Colors.orange.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        degraded ? l10n.deviceCompromisedDegraded : l10n.deviceCompromised,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      leading: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 20),
      actions: const [SizedBox.shrink()],
    );
  }

  /// Warnt, wenn die eigenen Schlüssel nicht auf dem Server liegen.
  ///
  /// Ohne sie kann niemand eine Session aufbauen und es kommt keine Nachricht
  /// an. Vorher verschwand dieser Fehlschlag in einem `catch`, das nur in
  /// Debug-Builds etwas ausgab — im TestFlight-Build war er unsichtbar, und
  /// die App wirkte, als sei alles in Ordnung.
  Widget _buildKeyPublishBanner(BuildContext context, KeyPublishState state) {
    final l10n = AppLocalizations.of(context)!;
    final denied = state == KeyPublishState.denied;
    return MaterialBanner(
      backgroundColor: denied ? Colors.red.shade900 : Colors.orange.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        denied ? l10n.keysNotPublishedDenied : l10n.keysNotPublishedFailed,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      leading: Icon(
        denied ? Icons.gpp_bad_rounded : Icons.cloud_off_rounded,
        color: Colors.white,
        size: 20,
      ),
      actions: const [SizedBox.shrink()],
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case _AppScreen.setup:
        return SetupScreen(
          key: const ValueKey('setup'),
          onSetupComplete: () => _navigateTo(_AppScreen.calculator),
        );

      case _AppScreen.language:
        return LanguageScreen(
          key: const ValueKey('language'),
          onContinue: () => _navigateTo(_AppScreen.tutorial),
        );

      case _AppScreen.welcomeBack:
        return const WelcomeBackScreen(key: ValueKey('welcome_back'));

      case _AppScreen.tutorial:
        return TutorialScreen(
          key: const ValueKey('tutorial'),
          onComplete: () => _navigateTo(_AppScreen.setup),
        );

      case _AppScreen.vaultPassword:
        return VaultPasswordScreen(
          key: const ValueKey('vault_password'),
          onVerify: (password) async {
            final storage = context.read<SecureStorageService>();
            final ok = await storage.verifyVaultPassword(password);
            if (ok) await _unlockMessenger();
            return ok;
          },
          onCancel: () => _navigateTo(_AppScreen.calculator),
          onEmergencyWipe: _handleEmergencyWipe,
        );

      case _AppScreen.calculator:
        return CalculatorScreen(
          key: const ValueKey('calculator'),
          onSecretCode: _onSecretCode,
          onDeleteCode: () => _handleEmergencyWipe(),
        );

      case _AppScreen.messenger:
        return ChatListScreen(
          key: const ValueKey('messenger'),
          onSettingsTap: () => _navigateTo(_AppScreen.settings),
          onChatTap: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onNewChat: () => _navigateTo(_AppScreen.newChat),
          onEmergencyWipe: _handleEmergencyWipe,
          onBack: _backToCalculator,
        );

      case _AppScreen.chat:
        if (_selectedChat == null) {
          _navigateTo(_AppScreen.messenger);
          return const SizedBox.shrink();
        }
        return ChatScreen(
          key: ValueKey('chat_${_selectedChat?.id}'),
          chat: _selectedChat!,
          onEmergencyWipe: _handleEmergencyWipe,
          onBack: () => _navigateTo(_AppScreen.messenger),
        );

      case _AppScreen.newChat:
        return NewChatScreen(
          key: const ValueKey('new_chat'),
          onChatCreated: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onBack: () => _navigateTo(_AppScreen.messenger),
          onScanQr: () => _navigateTo(_AppScreen.qrScanner),
        );

      case _AppScreen.qrScanner:
        return QrScannerScreen(
          key: const ValueKey('qr_scanner'),
          onChatCreated: (chat) {
            _selectedChat = chat;
            _navigateTo(_AppScreen.chat);
          },
          onBack: () => _navigateTo(_AppScreen.newChat),
        );

      case _AppScreen.settings:
        return SettingsScreen(
          key: const ValueKey('settings'),
          onEmergencyWipe: _handleEmergencyWipe,
          onBack: () => _navigateTo(_AppScreen.messenger),
          userId: context.read<MessengerProvider>().userId,
        );
    }
  }
}
