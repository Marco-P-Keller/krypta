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
import 'services/emergency/emergency_wipe_service.dart';
import 'services/platform/platform_security_service.dart';
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
  Chat? _selectedChat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When app goes to background, always lock back to calculator.
  /// This ensures the messenger is never visible when returning to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_currentScreen != _AppScreen.calculator &&
          _currentScreen != _AppScreen.setup &&
          _currentScreen != _AppScreen.tutorial) {
        // Disable screenshot protection and return to calculator
        final platform = context.read<PlatformSecurityService>();
        platform.disableScreenshotProtection();
        if (mounted) {
          setState(() {
            _currentScreen = _AppScreen.calculator;
            _selectedChat = null;
          });
        }
      }
    }
  }

  Future<void> _initialize() async {
    final storage = context.read<SecureStorageService>();
    final decoy = context.read<DecoyProvider>();
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
    final storage = context.read<SecureStorageService>();
    final platform = context.read<PlatformSecurityService>();

    final biometricEnabled = await storage.isBiometricEnabled();

    if (biometricEnabled) {
      final authenticated = await platform.authenticate(
        reason: 'Unlock Krypta Messenger',
      );
      if (!authenticated || !mounted) return;
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

    await messenger.initialize();
    await platform.enableScreenshotProtection();

    if (mounted) setState(() => _currentScreen = _AppScreen.messenger);
  }

  Future<void> _handleEmergencyWipe() async {
    final wipeService = context.read<EmergencyWipeService>();
    final messenger = context.read<MessengerProvider>();
    final platform = context.read<PlatformSecurityService>();

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
    final platform = context.read<PlatformSecurityService>();
    platform.disableScreenshotProtection();
    setState(() => _currentScreen = _AppScreen.calculator);
  }

  void _navigateTo(_AppScreen screen) => setState(() => _currentScreen = screen);

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _buildCurrentScreen(),
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
