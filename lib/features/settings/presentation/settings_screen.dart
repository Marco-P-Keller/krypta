import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/platform/platform_security_service.dart';
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

          // Security Codes
          _SectionHeader(l10n.securitySettings),
          _Card(isDark: isDark, children: [
            _NavTile(
              icon: Icons.lock_outline_rounded,
              title: l10n.changeSecretCode,
              onTap: () => _showChangeCodeDialog(
                  l10n.changeSecretCode, storage.saveSecretCode),
            ),
            _Divider(isDark: isDark),
            _NavTile(
              icon: Icons.shield_outlined,
              title: l10n.changeDecoyCode,
              onTap: () => _showChangeCodeDialog(
                  l10n.changeDecoyCode, storage.saveDecoyCode),
            ),
            _Divider(isDark: isDark),
            _NavTile(
              icon: Icons.delete_outline_rounded,
              title: l10n.changeDeleteCode,
              iconColor: AppColors.destructive,
              onTap: () => _showChangeCodeDialog(
                  l10n.changeDeleteCode, storage.saveDeleteCode),
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
              onTap: () => _showVaultPasswordDialog(context),
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
