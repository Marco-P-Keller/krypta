import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'features/auth/presentation/setup_screen.dart';
import 'features/auth/presentation/tutorial_screen.dart';
import 'features/auth/presentation/vault_password_screen.dart';
import 'features/calculator/presentation/calculator_screen.dart';
import 'features/decoy/decoy_provider.dart';
import 'features/messenger/data/models/chat_model.dart';
import 'features/messenger/logic/messenger_provider.dart';
import 'features/messenger/presentation/chat_list_screen.dart';
import 'features/messenger/presentation/chat_screen.dart';
import 'features/messenger/presentation/new_chat_screen.dart';
import 'features/messenger/presentation/qr_scanner_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'security/device/device_integrity_policy.dart';
import 'services/emergency/emergency_wipe_service.dart';
import 'services/platform/platform_security_service.dart';
import 'services/storage/encrypted_local_store.dart';
import 'services/storage/secure_storage_service.dart';
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
      supportedLocales: const [
        Locale('en'),
        Locale('de'),
      ],
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
  setup,
  tutorial,
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
  /// Screenshot protection stays active throughout the messenger session,
  /// so the app-switcher snapshot is already covered by the OS privacy mask.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isBackgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (isBackgrounded) {
      // Evict stale ratchet state entries (containing private keys) from memory.
      // This reduces the window where sensitive cryptographic material is in RAM.
      context.read<EncryptedLocalStore>().evictStaleCacheEntries();
      // C6: stop periodic integrity polling while backgrounded — the resume
      // path re-runs a one-shot check and _unlockMessenger re-starts it.
      context.read<DeviceIntegrityPolicyService>().stopPeriodicChecks();

      if (_currentScreen != _AppScreen.calculator &&
          _currentScreen != _AppScreen.setup &&
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
      integrity.recheck().then((_) {
        if (!mounted) return;
        final action = integrity.enforce();
        if (action != _deviceAction) {
          setState(() => _deviceAction = action);
        }
      });
      context.read<EncryptedLocalStore>().evictStaleCacheEntries();
    }
  }

  Future<void> _initialize() async {
    // Capture context references before async gaps.
    final integrity = context.read<DeviceIntegrityPolicyService>();
    final storage = context.read<SecureStorageService>();
    final decoy = context.read<DecoyProvider>();

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
        _currentScreen = _AppScreen.tutorial;
        _isInitialized = true;
      });
      return;
    }

    // Ensure decoy files always exist on disk — prevents forensic
    // distinction based on file existence patterns.
    try {
      await decoy.ensureDecoyFilesExist();
    } catch (_) {}

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
      final authenticated = await platform.authenticate(
        reason: 'Unlock Krypta Messenger',
      );
      if (!mounted) return;
      if (!authenticated) {
        // H4: unify biometric fails into the vault counter so an attacker
        // cannot burn through biometric attempts and then get a fresh
        // 5-attempt vault budget.
        await storage.incrementVaultFailCount();
        final fails = await storage.getVaultFailCount();
        if (fails >= SecureStorageService.maxVaultAttempts) {
          await _handleEmergencyWipe();
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

  Future<void> _unlockMessenger() async {
    final platform = context.read<PlatformSecurityService>();
    final messenger = context.read<MessengerProvider>();
    final integrity = context.read<DeviceIntegrityPolicyService>();

    // Fail-closed: enable screenshot protection BEFORE showing messenger
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
      child: showWarning && isMessengerScreen
          ? _wrapWithIntegrityWarning(screen)
          : screen,
    );
  }

  /// Wraps a screen with a persistent device integrity warning banner.
  Widget _wrapWithIntegrityWarning(Widget screen) {
    final degraded = _deviceAction == DeviceIntegrityAction.warnAndDegrade;
    return Column(
      key: ValueKey('integrity_warn_${screen.key}'),
      children: [
        MaterialBanner(
          backgroundColor: Colors.orange.shade900,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          content: Text(
            degraded
                ? 'Gerät möglicherweise kompromittiert. '
                  'Hardware-Sicherheit deaktiviert.'
                : 'Gerät möglicherweise kompromittiert.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          leading: const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 20),
          actions: const [SizedBox.shrink()],
        ),
        Expanded(child: screen),
      ],
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case _AppScreen.setup:
        return SetupScreen(
          key: const ValueKey('setup'),
          onSetupComplete: () => _navigateTo(_AppScreen.calculator),
        );

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
