import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/storage_keys.dart';
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
  bool _screenshotProtection = true;
  bool _biometricAvailable = false;
  bool _vaultPasswordEnabled = false;
  bool _pushPrivacyEnabled = false;
  bool _deliveryReceiptsEnabled = false;
  bool _readReceiptsEnabled = false;
  DeviceIntegrityLevel? _deviceIntegrityLevel;
  HardwareSecurityLevel? _hardwareSecurityLevel;
  bool _isHardwareWrapped = false;

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

    // Vault password takes priority — it's the real security layer
    if (_vaultPasswordEnabled) {
      return await _showReAuthDialog();
    }

    // Fallback: biometric if available
    if (_biometricAvailable && _biometricEnabled) {
      return await platform.authenticate(
        reason: 'Sicherheitseinstellungen ändern',
      );
    }

    // No vault or biometric — allow (but user should set vault password)
    return true;
  }

  Future<bool> _showReAuthDialog() async {
    final storage = context.read<SecureStorageService>();
    final controller = TextEditingController();
    bool? result;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentifizierung'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tresor-Passwort eingeben um Sicherheitseinstellungen zu ändern.',
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
                final ok = await storage.verifyVaultPassword(controller.text);
                result = ok;
                if (ctx.mounted) Navigator.of(ctx).pop();
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
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await storage.verifyVaultPassword(controller.text);
              result = ok;
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    );

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

  Future<void> _toggleScreenshotProtection(bool value) async {
    final platform = context.read<PlatformSecurityService>();
    if (value) {
      await platform.enableScreenshotProtection();
    } else {
      await platform.disableScreenshotProtection();
    }
    if (mounted) setState(() => _screenshotProtection = value);
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
            child: const Text('Cancel'),
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
                      const SnackBar(
                        content: Text('Code already in use for another action.'),
                      ),
                    );
                  }
                  return;
                }
                await onSave(code);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                AppLocalizations.of(context)!.privacyPolicy,
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
                  'Krypta ECC — Datenschutzerklärung\n\n'
                  'Stand: April 2026\n\n'
                  '1. Verantwortlicher\n'
                  'Connexa GmbH\n'
                  'Kontakt: https://connexa-gmbh.ch\n\n'
                  '2. Welche Daten werden erhoben?\n'
                  'Krypta erhebt so wenig Daten wie technisch möglich:\n'
                  '• Anonyme Firebase-ID (keine E-Mail, kein Name, keine Telefonnummer)\n'
                  '• Öffentlicher Verschlüsselungsschlüssel (X25519)\n'
                  '• FCM-Push-Token (für Benachrichtigungen)\n\n'
                  '3. Verschlüsselung\n'
                  'Alle Nachrichten sind Ende-zu-Ende-verschlüsselt (Signal-Protokoll: X3DH + Double Ratchet). '
                  'Der Server hat zu keinem Zeitpunkt Zugriff auf den Klartext Ihrer Nachrichten. '
                  'Verschlüsselung: XChaCha20-Poly1305. Passwort-Hashing: Argon2id.\n\n'
                  '4. Datenspeicherung\n'
                  '• Nachrichten werden nur auf Ihrem Gerät gespeichert (verschlüsselt)\n'
                  '• Der Server fungiert nur als temporärer Relay — Nachrichten werden nach Zustellung gelöscht\n'
                  '• Schlüssel werden im iOS Keychain / Android Keystore gespeichert\n\n'
                  '5. Keine Tracker\n'
                  'Krypta enthält keine Analyse-Tools, keine Werbung und keine Tracker (0 von 432 bekannten Trackern).\n\n'
                  '6. Datenweitergabe\n'
                  'Es werden keine personenbezogenen Daten an Dritte weitergegeben. '
                  'Google Firebase wird als Infrastruktur-Anbieter verwendet (anonyme Authentifizierung und Push-Benachrichtigungen).\n\n'
                  '7. Datenlöschung\n'
                  'Sie können jederzeit alle Ihre Daten unwiderruflich löschen:\n'
                  '• In den Einstellungen über "Alles löschen"\n'
                  '• Durch Eingabe des Lösch-Codes im Taschenrechner\n'
                  'Dabei werden alle lokalen Daten, Schlüssel und Server-Daten vernichtet.\n\n'
                  '8. Ihre Rechte (DSGVO)\n'
                  'Sie haben das Recht auf Auskunft, Berichtigung, Löschung und Datenübertragbarkeit. '
                  'Kontaktieren Sie uns unter: https://connexa-gmbh.ch\n\n'
                  '9. Änderungen\n'
                  'Diese Datenschutzerklärung kann aktualisiert werden. '
                  'Die aktuelle Version ist immer in der App einsehbar.',
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
          // Account
          if (widget.userId != null) ...[
            _SectionHeader(l10n.accountSection),
            _Card(isDark: isDark, children: [
              _CopyTile(
                icon: Icons.person_outline_rounded,
                title: l10n.userIdLabel,
                value: widget.userId!,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: widget.userId!));
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
            _SectionHeader('Gerätesicherheit'),
            _Card(isDark: isDark, children: [
              _NavTile(
                icon: _deviceIntegrityLevel == DeviceIntegrityLevel.clean
                    ? Icons.verified_user_rounded
                    : Icons.warning_amber_rounded,
                iconColor: _deviceIntegrityLevel == DeviceIntegrityLevel.clean
                    ? AppColors.success
                    : Colors.orange,
                title: switch (_deviceIntegrityLevel!) {
                  DeviceIntegrityLevel.clean => 'Gerät sicher',
                  DeviceIntegrityLevel.compromised =>
                    'Kompromittierung erkannt',
                  DeviceIntegrityLevel.unknown => 'Status unbekannt',
                },
                subtitle: switch (_deviceIntegrityLevel!) {
                  DeviceIntegrityLevel.clean =>
                    'Keine Root/Jailbreak/Frida-Indikatoren',
                  DeviceIntegrityLevel.compromised =>
                    'Root, Jailbreak oder Instrumentierung erkannt. '
                        'Hardware-Sicherheit deaktiviert.',
                  DeviceIntegrityLevel.unknown =>
                    'Integritätsprüfung fehlgeschlagen — '
                        'eingeschränkter Modus aktiv.',
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
                    HardwareSecurityLevel.hardwareEnclave =>
                      'Hardware-Enklave',
                    HardwareSecurityLevel.trustedExecution =>
                      'TEE-Schlüsselspeicher',
                    HardwareSecurityLevel.softwareOnly =>
                      'Software-Schlüsselspeicher',
                  },
                  subtitle: _isHardwareWrapped
                      ? 'Datenbankschlüssel an Hardware gebunden'
                      : switch (_hardwareSecurityLevel!) {
                          HardwareSecurityLevel.hardwareEnclave =>
                            'StrongBox/Secure Enclave verfügbar',
                          HardwareSecurityLevel.trustedExecution =>
                            'Schlüssel im Trusted Execution Environment',
                          HardwareSecurityLevel.softwareOnly =>
                            'Keine Hardware-Sicherheit verfügbar',
                        },
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
            _SwitchTile(
              icon: Icons.screenshot_monitor_outlined,
              title: l10n.screenshotProtection,
              subtitle: l10n.screenshotDescription,
              value: _screenshotProtection,
              onChanged: _toggleScreenshotProtection,
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
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
              title: 'Push-Privatsphäre',
              subtitle: _pushPrivacyEnabled
                  ? 'Aktiv — Nachrichten werden per Polling abgerufen'
                  : 'Deaktiviert — Push-Benachrichtigungen aktiv',
              value: _pushPrivacyEnabled,
              onChanged: _togglePushPrivacy,
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              icon: Icons.mark_email_read_outlined,
              title: 'Lesebestätigungen',
              subtitle: _readReceiptsEnabled
                  ? 'Aktiv — Absender sieht, wann du liest'
                  : 'Deaktiviert — maximale Privatsphäre',
              value: _readReceiptsEnabled,
              onChanged: _toggleReadReceipts,
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              icon: Icons.done_all_rounded,
              title: 'Zustellbestätigungen',
              subtitle: _deliveryReceiptsEnabled
                  ? 'Aktiv — Absender sieht, wann zugestellt'
                  : 'Deaktiviert — maximale Privatsphäre',
              value: _deliveryReceiptsEnabled,
              onChanged: _toggleDeliveryReceipts,
              isDark: isDark,
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
          ]),
          const SizedBox(height: 28),

          // About
          _SectionHeader(l10n.about),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.info_outline_rounded,
              title: l10n.about,
              subtitle: l10n.version(AppConstants.appVersion),
              onTap: () {},
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
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.destructive,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
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

  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    required this.onTap,
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
          Icon(Icons.chevron_right_rounded,
              size: 18,
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight),
      onTap: onTap,
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
      activeThumbColor: AppColors.success,
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
      trailing: Icon(Icons.copy_rounded,
          size: 16,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight),
      onTap: onCopy,
    );
  }
}
