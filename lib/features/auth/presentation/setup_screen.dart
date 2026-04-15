import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../security/key_management/key_manager.dart';
import '../../../services/firebase/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  const SetupScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _controllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  late final AnimationController _progressCtrl;
  bool _isLoading = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1 / 3,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _progressCtrl.dispose();
    super.dispose();
  }

  String? _validateCode(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    if (v.length < AppConstants.minCodeLength) {
      return 'Min ${AppConstants.minCodeLength} digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) return 'Digits only';
    return null;
  }

  void _next() {
    if (_validateCode(_controllers[_step].text) != null) return;
    if (_step < 2) {
      setState(() => _step++);
      _progressCtrl.animateTo((_step + 1) / 3);
    } else {
      _completeSetup();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _progressCtrl.animateTo((_step + 1) / 3);
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);
    try {
      final storage = context.read<SecureStorageService>();
      final auth = context.read<AuthService>();
      final keyManager = context.read<KeyManager>();
      final firestore = context.read<FirestoreService>();

      final user = await auth.signInAnonymously();
      if (user == null) throw Exception('Auth failed');

      final keyPair = await keyManager.getOrCreateIdentityKeyPair();
      await firestore.registerPublicKey(
        userId: user.uid,
        publicKeyBase64: keyPair.publicKeyBase64,
      );

      await Future.wait([
        storage.saveSecretCode(_controllers[0].text),
        storage.saveDecoyCode(_controllers[1].text),
        storage.saveDeleteCode(_controllers[2].text),
        storage.saveUserId(user.uid),
        storage.markSetupComplete(),
      ]);

      if (mounted) widget.onSetupComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _stepData = [
    (
      icon: Icons.lock_outline_rounded,
      color: AppColors.accent,
      title: 'Secret Code',
      subtitle: 'Enter this in the calculator to open your vault.',
    ),
    (
      icon: Icons.shield_outlined,
      color: Color(0xFF30D158),
      title: 'Decoy Code',
      subtitle: 'Opens a fake empty messenger. Use when coerced.',
    ),
    (
      icon: Icons.delete_forever_outlined,
      color: AppColors.destructive,
      title: 'Delete Code',
      subtitle: 'Instantly erases everything. Use in emergencies only.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = _stepData[_step];

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            AnimatedBuilder(
              animation: _progressCtrl,
              builder: (context, child) => LinearProgressIndicator(
                value: _progressCtrl.value,
                backgroundColor:
                    isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                color: step.color,
                minHeight: 2,
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),

                    // Icon
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_step),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: step.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                        child: Icon(step.icon, color: step.color, size: 32),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Title
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        key: ValueKey('title$_step'),
                        step.title,
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight,
                                ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // Subtitle
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        key: ValueKey('sub$_step'),
                        step.subtitle,
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                  height: 1.5,
                                ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // PIN input
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: TextFormField(
                        key: ValueKey('input$_step'),
                        controller: _controllers[_step],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                              AppConstants.maxCodeLength),
                        ],
                        obscureText: true,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        onFieldSubmitted: (_) => _next(),
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                              letterSpacing: 16,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '• • • • •',
                          hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            fontSize: 28,
                            letterSpacing: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                  AppSpacing.screenPadding,
                  AppSpacing.lg),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 80),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isLoading ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: step.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_step < 2 ? 'Continue' : 'Finish'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
