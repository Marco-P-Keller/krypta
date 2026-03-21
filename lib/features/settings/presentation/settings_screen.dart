import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../calculator/logic/code_detector.dart';
import '../../../services/platform/platform_security_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../theme/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<SecureStorageService>();
    final platform = context.read<PlatformSecurityService>();

    final biometric = await storage.isBiometricEnabled();
    final available = await platform.isBiometricAvailable;
    final vaultPw = await storage.isVaultPasswordEnabled();

    if (mounted) {
      setState(() {
        _biometricEnabled = biometric;
        _biometricAvailable = available;
        _vaultPasswordEnabled = vaultPw;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final storage = context.read<SecureStorageService>();
    await storage.setBiometricEnabled(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _toggleScreenshotProtection(bool value) async {
    final platform = context.read<PlatformSecurityService>();
    if (value) {
      await platform.enableScreenshotProtection();
    } else {
      await platform.disableScreenshotProtection();
    }
    setState(() => _screenshotProtection = value);
  }

  void _showChangeCodeDialog(String title, Future<void> Function(String) onSave) {
    final controller = TextEditingController();
    final codeDetector = context.read<CodeDetector>();
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
                await onSave(code);
                await codeDetector.loadCodes();
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

  void _showVaultPasswordDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final storage = context.read<SecureStorageService>();

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
                    _showSetVaultPassword(context);
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
      _showSetVaultPassword(context);
    }
  }

  void _showSetVaultPassword(BuildContext context) {
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
                    if (pwError != null) {
                      setDialogState(() => pwError = null);
                    }
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
        title: Text(l10n.settingsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // User ID
          if (widget.userId != null) ...[
            _buildSectionHeader(l10n.accountSection),
            ListTile(
              leading: const Icon(Icons.person_outline, color: AppColors.primary),
              title: Text(l10n.userIdLabel),
              subtitle: Text(
                widget.userId!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.userId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.userIdCopied)),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // Security codes
          _buildSectionHeader(l10n.securitySettings),
          _buildTile(
            icon: Icons.lock_outline,
            title: l10n.changeSecretCode,
            onTap: () => _showChangeCodeDialog(
              l10n.changeSecretCode,
              storage.saveSecretCode,
            ),
          ),
          _buildTile(
            icon: Icons.shield_outlined,
            title: l10n.changeDecoyCode,
            onTap: () => _showChangeCodeDialog(
              l10n.changeDecoyCode,
              storage.saveDecoyCode,
            ),
          ),
          _buildTile(
            icon: Icons.delete_outline,
            title: l10n.changeDeleteCode,
            onTap: () => _showChangeCodeDialog(
              l10n.changeDeleteCode,
              storage.saveDeleteCode,
            ),
          ),

          // Privacy
          const SizedBox(height: 16),
          _buildSectionHeader(l10n.privacySection),
          if (_biometricAvailable)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint, color: AppColors.primary),
              title: Text(l10n.biometricUnlock),
              subtitle: Text(
                l10n.biometricDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: _biometricEnabled,
              onChanged: _toggleBiometric,
              activeTrackColor: AppColors.primary,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.screenshot_outlined, color: AppColors.primary),
            title: Text(l10n.screenshotProtection),
            subtitle: Text(
              l10n.screenshotDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _screenshotProtection,
            onChanged: _toggleScreenshotProtection,
            activeTrackColor: AppColors.primary,
          ),
          const Divider(indent: 16, endIndent: 16, height: 1),
          ListTile(
            leading: const Icon(Icons.shield_rounded, color: AppColors.primary),
            title: Text(l10n.vaultPassword),
            subtitle: Text(
              _vaultPasswordEnabled
                  ? l10n.changeVaultPassword
                  : l10n.vaultPasswordDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: _vaultPasswordEnabled
                ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                : const Icon(Icons.chevron_right, size: 20),
            onTap: () => _showVaultPasswordDialog(context),
          ),

          // About
          const SizedBox(height: 16),
          _buildTile(
            icon: Icons.info_outline,
            title: l10n.about,
            subtitle: l10n.version(AppConstants.appVersion),
            onTap: () {},
          ),

          // Danger zone
          const SizedBox(height: 32),
          _buildSectionHeader(l10n.dangerZone, isDestructive: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onEmergencyWipe,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.destructive,
                      side: const BorderSide(color: AppColors.destructive),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: Text(l10n.emergencyDelete),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.emergencyDeleteDescription,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDestructive ? AppColors.destructive : AppColors.textTertiaryDark,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
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
