import 'package:flutter/material.dart';

import 'sicherheitsdetails_screen.dart';
import 'package:flutter/services.dart';
import '../../../services/platform/clipboard_helper.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/storage_keys.dart';
import '../../auth/presentation/tutorial_screen.dart';
import 'language_screen.dart';
import '../../../core/locale/locale_controller.dart';
import '../../messenger/logic/messenger_provider.dart';
import '../../../security/device/device_integrity_policy.dart';
import '../../../security/hardware/hardware_security_binding.dart';
import '../../../services/platform/platform_security_service.dart';
import '../../../services/storage/encrypted_local_store.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onEmergencyWipe;
  final VoidCallback onBack;
  final String? userId;

  const SettingsScreen({
    super.key,
    required this.onEmergencyWipe,
    required this.onBack,
    this.userId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  /// Ob beide Seiten von Screenshots und Bildschirmaufnahmen erfahren.
  ///
  /// Hier stand einmal ein „Screenshot-Schutz". Der beruhte auf
  /// undokumentiertem Verhalten, wirkte ab iOS 26 nicht mehr — und der
  /// Schalter zeigte trotzdem „an". Eine App, die einen Schutz behauptet, den
  /// sie nicht hat, ist schlechter als eine, die ehrlich ist. Verhindern
  /// laesst sich ein Screenshot auf iOS ohnehin nicht; melden schon.
  bool _biometricAvailable = false;
  bool _vaultPasswordEnabled = false;
  bool _pushPrivacyEnabled = false;
  bool _deliveryReceiptsEnabled = false;
  bool _readReceiptsEnabled = false;
  DeviceIntegrityLevel? _deviceIntegrityLevel;
  HardwareSecurityLevel? _hardwareSecurityLevel;
  bool _isHardwareWrapped = false;

  /// B3 single-flight guard: prevents two near-simultaneous re-auth
  /// submits (Enter key + tap on Confirm) from racing the read-modify-
  /// write counter and consuming only one of two failed attempts.
  bool _reAuthInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<SecureStorageService>();
    final platform = context.read<PlatformSecurityService>();

    final integrity = context.read<DeviceIntegrityPolicyService>();
    final hardware = context.read<HardwareSecurityBinding>();
    final localStore = context.read<EncryptedLocalStore>();

    final biometric = await storage.isBiometricEnabled();
    final available = await platform.isBiometricAvailable;
    final vaultPw = await storage.isVaultPasswordEnabled();
    final pushPrivacy = await storage.isPushPrivacyEnabled();
    final deliveryReceipts = await storage.isDeliveryReceiptsEnabled();
    final readReceipts = await storage.isReadReceiptsEnabled();

    if (mounted) {
      setState(() {
        _biometricEnabled = biometric;
        _biometricAvailable = available;
        _vaultPasswordEnabled = vaultPw;
        _pushPrivacyEnabled = pushPrivacy;
        _deliveryReceiptsEnabled = deliveryReceipts;
        _readReceiptsEnabled = readReceipts;
        _deviceIntegrityLevel = integrity.lastResult?.level;
        _hardwareSecurityLevel = hardware.level;
        _isHardwareWrapped = localStore.isHardwareWrapped;
      });
    }
  }

  /// Re-authenticate before critical security changes.
  ///
  /// If vault password is enabled, requires vault password.
  /// Otherwise uses biometric if available.
  /// Returns true if authentication succeeded.
  Future<bool> _reAuthenticate() async {
    final platform = context.read<PlatformSecurityService>();
    final storage = context.read<SecureStorageService>();

    // Vault password takes priority — it's the real security layer
    if (_vaultPasswordEnabled) {
      final ok = await _showReAuthDialog();
      // B3: if the dialog's fail counter has reached the wipe threshold
      // trigger emergency wipe immediately, mirroring VaultPasswordScreen.
      if (!ok &&
          await storage.getVaultFailCount() >=
              SecureStorageService.maxVaultAttempts) {
        widget.onEmergencyWipe();
      }
      return ok;
    }

    // Fallback: biometric if available
    if (_biometricAvailable && _biometricEnabled) {
      return await platform.authenticate(
        reason: AppLocalizations.of(context)!.securitySettingsReason,
      );
    }

    // No vault or biometric — allow (but user should set vault password)
    return true;
  }

  Future<bool> _showReAuthDialog() async {
    final storage = context.read<SecureStorageService>();
    final controller = TextEditingController();
    bool? result;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          // Sonst legt sich der Inhalt bei offener Tastatur und grosser
          // Systemschrift ueber die Knopfzeile, statt zu scrollen.
          scrollable: true,
          title: Text(AppLocalizations.of(context)!.authentication),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.vaultPasswordReAuthHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '••••••••••',
                  prefixIcon: Icon(Icons.lock_outline, size: 20),
                ),
                onSubmitted: (_) async {
                  // B3: route re-auth through the same unified counter as
                  // the main vault password screen. Single-flight guard
                  // prevents Enter+tap from racing two fails into one
                  // increment (read-modify-write on FlutterSecureStorage).
                  if (_reAuthInFlight) return;
                  _reAuthInFlight = true;
                  try {
                    if (await storage.getVaultFailCount() >=
                        SecureStorageService.maxVaultAttempts) {
                      result = false;
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      return;
                    }
                    final ok =
                        await storage.verifyVaultPassword(controller.text);
                    if (ok) {
                      await storage.resetVaultFailCount();
                    } else {
                      await storage.incrementVaultFailCount();
                    }
                    result = ok;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } finally {
                    _reAuthInFlight = false;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                result = false;
                Navigator.of(ctx).pop();
              },
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                // B3: same unified-counter + single-flight guard as the
                // onSubmitted handler. Both entry points must share the
                // lock so Enter-then-tap cannot produce two concurrent
                // increments that lose one failed attempt.
                if (_reAuthInFlight) return;
                _reAuthInFlight = true;
                try {
                  if (await storage.getVaultFailCount() >=
                      SecureStorageService.maxVaultAttempts) {
                    result = false;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    return;
                  }
                  final ok =
                      await storage.verifyVaultPassword(controller.text);
                  if (ok) {
                    await storage.resetVaultFailCount();
                  } else {
                    await storage.incrementVaultFailCount();
                  }
                  result = ok;
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } finally {
                  _reAuthInFlight = false;
                }
              },
              child: Text(AppLocalizations.of(ctx)!.confirm),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    return result ?? false;
  }

  Future<void> _toggleBiometric(bool value) async {
    final storage = context.read<SecureStorageService>();
    // Re-auth before changing security settings
    if (!await _reAuthenticate()) return;

    await storage.setBiometricEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _togglePushPrivacy(bool value) async {
    final messenger = context.read<MessengerProvider>();
    await messenger.setPushPrivacyEnabled(value);
    if (mounted) setState(() => _pushPrivacyEnabled = value);
  }

  Future<void> _toggleDeliveryReceipts(bool value) async {
    final messenger = context.read<MessengerProvider>();
    await messenger.setDeliveryReceiptsEnabled(value);
    if (mounted) setState(() => _deliveryReceiptsEnabled = value);
  }

  Future<void> _toggleReadReceipts(bool value) async {
    final messenger = context.read<MessengerProvider>();
    await messenger.setReadReceiptsEnabled(value);
    if (mounted) setState(() => _readReceiptsEnabled = value);
  }

  void _showChangeCodeDialog(
    String title,
    Future<void> Function(String) onSave, {
    required String currentKey,
  }) async {
    // Re-auth before changing codes
    if (!await _reAuthenticate()) return;

    if (!mounted) return;
    final storage = context.read<SecureStorageService>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        // Sonst legt sich der Inhalt bei offener Tastatur und grosser
        // Systemschrift ueber die Knopfzeile, statt zu scrollen.
        scrollable: true,
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(AppConstants.maxCodeLength),
          ],
          decoration: const InputDecoration(hintText: '••••'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controller.text;
              if (code.length >= AppConstants.minCodeLength) {
                // Prevent collision with other codes
                final collides = await storage.codeCollides(
                    code, excludeKey: currentKey);
                if (collides) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(ctx)!.codeAlreadyInUse),
                      ),
                    );
                  }
                  return;
                }
                await onSave(code);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  static bool _isStrongPassword(String pw) {
    if (pw.length < 10) return false;
    if (!pw.contains(RegExp(r'[A-Z]'))) return false;
    if (!pw.contains(RegExp(r'[a-z]'))) return false;
    if (!pw.contains(RegExp(r'[0-9]'))) return false;
    if (!pw.contains(RegExp(r'[^A-Za-z0-9]'))) return false;
    return true;
  }

  void _showPrivacyPolicy(BuildContext context, bool isDark) {
    // Vor showModalBottomSheet gelesen: der Bauer unten bekommt einen eigenen
    // context, und der Text soll aus derselben Sprache kommen wie der Rest.
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                l10n.privacyPolicy,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Text(
                  l10n.privacyPolicyBody,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVaultPasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final storage = context.read<SecureStorageService>();

    // Re-auth before changing vault password
    if (_vaultPasswordEnabled && !await _reAuthenticate()) return;

    if (!mounted) return;

    if (_vaultPasswordEnabled) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              top: 12,
              bottom: MediaQuery.of(ctx).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.dividerDark : AppColors.dividerLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: Text(l10n.changeVaultPassword),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showSetVaultPassword();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppColors.destructive),
                  title: Text(l10n.removeVaultPassword,
                      style: const TextStyle(color: AppColors.destructive)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final scaffold = ScaffoldMessenger.of(context);
                    await storage.removeVaultPassword();
                    if (mounted) {
                      setState(() => _vaultPasswordEnabled = false);
                      scaffold.showSnackBar(
                        SnackBar(content: Text(l10n.vaultPasswordRemoved)),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    } else {
      _showSetVaultPassword();
    }
  }

  void _showSetVaultPassword() {
    final l10n = AppLocalizations.of(context)!;
    final storage = context.read<SecureStorageService>();
    final pwController = TextEditingController();
    final confirmController = TextEditingController();
    String? pwError;
    String? confirmError;
    bool obscure1 = true;
    bool obscure2 = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.setVaultPassword),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.vaultPasswordRules,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pwController,
                  obscureText: obscure1,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.newPassword,
                    errorText: pwError,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure1
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure1 = !obscure1),
                    ),
                  ),
                  onChanged: (_) {
                    setDialogState(() {
                      if (pwError != null) pwError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: obscure2,
                  decoration: InputDecoration(
                    hintText: l10n.confirmPassword,
                    errorText: confirmError,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure2
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure2 = !obscure2),
                    ),
                  ),
                  onChanged: (_) {
                    if (confirmError != null) {
                      setDialogState(() => confirmError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _PasswordStrength(password: pwController.text, l10n: l10n),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final pw = pwController.text;
                final confirm = confirmController.text;

                if (!_isStrongPassword(pw)) {
                  setDialogState(() => pwError = l10n.passwordTooWeak);
                  return;
                }
                if (pw != confirm) {
                  setDialogState(
                      () => confirmError = l10n.passwordsDoNotMatch);
                  return;
                }

                final scaffold = ScaffoldMessenger.of(context);
                await storage.setVaultPassword(pw);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  setState(() => _vaultPasswordEnabled = true);
                  scaffold.showSnackBar(
                    SnackBar(content: Text(l10n.vaultPasswordSet)),
                  );
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    ).then((_) {
      pwController.dispose();
      confirmController.dispose();
    });
  }

  void _openTutorial(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => TutorialScreen(
          onComplete: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        contentPadding:
            const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.shield_rounded,
                  color: AppColors.accent, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.appName,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.version(AppConstants.appVersion),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
            ),
            const SizedBox(height: 18),
            // Hier standen drei Algorithmusnamen. Sie waren zudem unvollstaendig
            // und ungenau: „Curve25519" verschwieg, dass es zwei Verfahren sind
            // (X25519 zum Austausch, Ed25519 zum Signieren), und HKDF fehlte
            // ganz. Wer die Namen sucht, findet sie jetzt vollstaendig in den
            // Sicherheitsdetails; hier steht, was die Sache bedeutet.
            Text(
              l10n.aboutSecurityLine,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SicherheitsdetailsScreen(),
                ));
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 36),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(l10n.securityDetails)),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.aboutClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storage = context.read<SecureStorageService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle,
            style: Theme.of(context).textTheme.titleLarge),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding, vertical: 16),
        children: [
          // Sprache — bewusst weit oben: wer die App in einer Sprache
          // vorfindet, die er nicht liest, soll nicht erst scrollen muessen.
          _SectionHeader(l10n.language),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.language_rounded,
              title: l10n.language,
              subtitle: LocaleController.labelFor(
                  context.watch<LocaleController>().locale),
              onTap: () => showLanguageSheet(context),
            ),
          ]),
          const SizedBox(height: 28),

          // Account
          if (widget.userId != null) ...[
            _SectionHeader(l10n.accountSection),
            _Card(isDark: isDark, children: [
              _CopyTile(
                icon: Icons.person_outline_rounded,
                title: l10n.userIdLabel,
                value: widget.userId!,
                onCopy: () {
                  // M2-Client: ephemeral copy with auto-clear (60s).
                  ClipboardHelper.copyEphemeral(widget.userId!);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.userIdCopied)));
                },
                isDark: isDark,
              ),
            ]),
            const SizedBox(height: 28),
          ],

          // Device Security Status
          if (_deviceIntegrityLevel != null) ...[
            _SectionHeader(l10n.deviceSecuritySection),
            _Card(isDark: isDark, children: [
              _NavTile(
                icon: _deviceIntegrityLevel == DeviceIntegrityLevel.clean
                    ? Icons.verified_user_rounded
                    : Icons.warning_amber_rounded,
                iconColor: _deviceIntegrityLevel == DeviceIntegrityLevel.clean
                    ? AppColors.success
                    : Colors.orange,
                title: switch (_deviceIntegrityLevel!) {
                  DeviceIntegrityLevel.clean => l10n.deviceSecure,
                  DeviceIntegrityLevel.compromised => l10n.deviceCompromisedDetected,
                  DeviceIntegrityLevel.unknown => l10n.deviceStatusUnknown,
                },
                subtitle: switch (_deviceIntegrityLevel!) {
                  DeviceIntegrityLevel.clean => l10n.deviceSecureSubtitle,
                  DeviceIntegrityLevel.compromised =>
                    l10n.deviceCompromisedSubtitle,
                  DeviceIntegrityLevel.unknown => l10n.deviceStatusUnknownSubtitle,
                },
                trailing: const SizedBox.shrink(),
                onTap: () {},
              ),
              if (_hardwareSecurityLevel != null) ...[
                _Divider(isDark: isDark),
                _NavTile(
                  icon: _isHardwareWrapped
                      ? Icons.hardware_rounded
                      : Icons.memory_rounded,
                  iconColor: _isHardwareWrapped
                      ? AppColors.success
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                  title: switch (_hardwareSecurityLevel!) {
                    HardwareSecurityLevel.hardwareEnclave => l10n.hardwareEnclave,
                    HardwareSecurityLevel.trustedExecution => l10n.hardwareTee,
                    HardwareSecurityLevel.softwareOnly => l10n.hardwareSoftware,
                  },
                  subtitle: _isHardwareWrapped
                      ? l10n.hardwareBoundSubtitle
                      : switch (_hardwareSecurityLevel!) {
                          HardwareSecurityLevel.hardwareEnclave =>
                            l10n.hardwareEnclaveSubtitle,
                          HardwareSecurityLevel.trustedExecution =>
                            l10n.hardwareTeeSubtitle,
                          HardwareSecurityLevel.softwareOnly =>
                            l10n.hardwareSoftwareSubtitle,
                        },
                  // Reine Anzeige: es gibt nichts einzustellen. Der Eintrag
                  // sieht aus wie vorher, reagiert aber nicht mehr auf Tippen.
                  interactive: false,
                  trailing: _isHardwareWrapped
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 18)
                      : const SizedBox.shrink(),
                  onTap: () {},
                ),
              ],
            ]),
            const SizedBox(height: 28),
          ],

          // Security Codes
          _SectionHeader(l10n.securitySettings),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.lock_outline_rounded,
              title: l10n.changeSecretCode,
              onTap: () => _showChangeCodeDialog(
                  l10n.changeSecretCode, storage.saveSecretCode,
                  currentKey: StorageKeys.secretCode),
            ),
            _Divider(isDark: isDark),
            _NavTile(
              icon: Icons.delete_outline_rounded,
              title: l10n.changeDeleteCode,
              iconColor: AppColors.destructive,
              onTap: () => _showChangeCodeDialog(
                  l10n.changeDeleteCode, storage.saveDeleteCode,
                  currentKey: StorageKeys.deleteCode),
            ),
          ]),
          const SizedBox(height: 28),

          // Privacy
          _SectionHeader(l10n.privacySection),
          _Card(isDark: isDark, children: [
            if (_biometricAvailable) ...[
              _SwitchTile(
                icon: Icons.fingerprint_rounded,
                title: l10n.biometricUnlock,
                subtitle: l10n.biometricDescription,
                value: _biometricEnabled,
                onChanged: _toggleBiometric,
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
            ],
            _NavTile(
              icon: Icons.shield_rounded,
              title: l10n.vaultPassword,
              subtitle: _vaultPasswordEnabled
                  ? l10n.changeVaultPassword
                  : l10n.vaultPasswordDescription,
              trailing: _vaultPasswordEnabled
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 18)
                  : null,
              onTap: _showVaultPasswordDialog,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              icon: Icons.wifi_off_rounded,
              title: l10n.pushPrivacy,
              subtitle: _pushPrivacyEnabled
                  ? l10n.pushPrivacyOn
                  : l10n.pushPrivacyOff,
              value: _pushPrivacyEnabled,
              onChanged: _togglePushPrivacy,
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              icon: Icons.mark_email_read_outlined,
              title: l10n.readReceipts,
              subtitle: _readReceiptsEnabled
                  ? l10n.readReceiptsOn
                  : l10n.readReceiptsOff,
              value: _readReceiptsEnabled,
              onChanged: _toggleReadReceipts,
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              icon: Icons.done_all_rounded,
              title: l10n.deliveryReceipts,
              subtitle: _deliveryReceiptsEnabled
                  ? l10n.deliveryReceiptsOn
                  : l10n.deliveryReceiptsOff,
              value: _deliveryReceiptsEnabled,
              onChanged: _toggleDeliveryReceipts,
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 28),

          // About
          _SectionHeader(l10n.about),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.info_outline_rounded,
              // Die Versionsnummer steht jetzt im Titel statt darunter — sie
              // ist das, wonach man hier sucht. Sie kommt über --dart-define
              // aus derselben Quelle wie CFBundleShortVersionString.
              title: '${l10n.appName} ${l10n.version(AppConstants.appVersion)}',
              onTap: () => _showAboutDialog(context, l10n),
            ),
            _Divider(isDark: isDark),
            _NavTile(
              icon: Icons.school_outlined,
              title: l10n.showTutorial,
              subtitle: l10n.showTutorialSubtitle,
              onTap: () => _openTutorial(context),
            ),
          ]),
          const SizedBox(height: 28),

          // Legal
          _SectionHeader(l10n.legalSection),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.description_outlined,
              title: l10n.privacyPolicy,
              onTap: () => _showPrivacyPolicy(context, isDark),
            ),
            _Divider(isDark: isDark),
            _NavTile(
              icon: Icons.collections_bookmark_outlined,
              title: l10n.openSourceLicenses,
              subtitle: l10n.openSourceLicensesSubtitle,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Krypta ECC',
                applicationVersion: AppConstants.appVersion,
              ),
            ),
          ]),
          const SizedBox(height: 40),

          // Danger zone
          _SectionHeader(l10n.dangerZone, isDestructive: true),
          _EmergencyButton(
            label: l10n.emergencyDelete,
            description: l10n.emergencyDeleteDescription,
            isDark: isDark,
            onPressed: widget.onEmergencyWipe,
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

}

class _EmergencyButton extends StatelessWidget {
  final String label;
  final String description;
  final bool isDark;
  final VoidCallback onPressed;

  const _EmergencyButton({
    required this.label,
    required this.description,
    required this.isDark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.destructive.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.destructive.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.destructive,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.destructive,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.destructive,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  final String password;
  final AppLocalizations l10n;

  const _PasswordStrength({required this.password, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final checks = <(String, bool)>[
      ('≥ 10', password.length >= 10),
      ('A-Z', password.contains(RegExp(r'[A-Z]'))),
      ('a-z', password.contains(RegExp(r'[a-z]'))),
      ('0-9', password.contains(RegExp(r'[0-9]'))),
      ('!@#\$', password.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: checks.map((check) {
        final (label, passed) = check;
        return Chip(
          label: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: passed ? Colors.white : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: passed ? AppColors.success : null,
          side: passed ? BorderSide.none : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDestructive;
  const _SectionHeader(this.title, {this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDestructive
                  ? AppColors.destructive
                  : (isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.33,
      indent: 52,
      color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback onTap;

  /// Ob der Eintrag auf Tippen reagiert.
  ///
  /// `false` macht ihn zur reinen Anzeige: gleiches Aussehen, aber kein Pfeil
  /// und keine Reaktion. Für Einträge, hinter denen es nichts einzustellen
  /// gibt und deren Pfeil sonst etwas verspricht, das nicht kommt.
  final bool interactive;

  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    required this.onTap,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Icon(icon,
          color: iconColor ??
              (isDark ? AppColors.accent : AppColors.accentLight),
          size: 22),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ))
          : null,
      trailing: trailing ??
          (interactive
              ? Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiaryLight)
              : null),
      onTap: interactive ? onTap : null,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isDark;
  final void Function(bool) onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon,
          color: isDark ? AppColors.accent : AppColors.accentLight, size: 22),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
      ),
      value: value,
      onChanged: onChanged,
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      activeTrackColor: AppColors.success,
    );
  }
}

class _CopyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isDark;
  final VoidCallback onCopy;

  const _CopyTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.isDark,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: isDark ? AppColors.accent : AppColors.accentLight, size: 22),
      title: Text(title),
      subtitle: Text(
        value,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
        overflow: TextOverflow.ellipsis,
      ),
      // Nur das Symbol kopiert. Die ID selbst ist Anzeige: wer sie liest oder
      // vorliest, soll sie nicht versehentlich in die Zwischenablage legen.
      trailing: IconButton(
        icon: Icon(Icons.copy_rounded,
            size: 16,
            color:
                isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight),
        tooltip: AppLocalizations.of(context)!.copy,
        onPressed: onCopy,
      ),
    );
  }
}
