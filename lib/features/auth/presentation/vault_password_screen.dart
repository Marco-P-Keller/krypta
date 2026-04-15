import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Full-screen vault password gate.
/// Shown after the calculator secret code, before the messenger.
class VaultPasswordScreen extends StatefulWidget {
  final Future<bool> Function(String password) onVerify;
  final VoidCallback onCancel;

  const VaultPasswordScreen({
    super.key,
    required this.onVerify,
    required this.onCancel,
  });

  @override
  State<VaultPasswordScreen> createState() => _VaultPasswordScreenState();
}

class _VaultPasswordScreenState extends State<VaultPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _controller.text;
    if (pw.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final ok = await widget.onVerify(pw);
    if (!mounted) return;

    if (!ok) {
      _controller.clear();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _isLoading = false;
        _error = AppLocalizations.of(context)!.wrongPassword;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Glow icon
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final progress = _shakeAnim.value;
                  final shake =
                      (progress * 6 * 3.14159).clamp(-1.0, 1.0) * 12;
                  return Transform.translate(
                    offset: Offset(shake * (1 - progress), 0),
                    child: child,
                  );
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.25),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_rounded,
                      size: 36, color: AppColors.accent),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text(
                l10n.vaultPasswordTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimaryDark,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                l10n.vaultPasswordHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              // Password field with shake animation
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final progress = _shakeAnim.value;
                  final shake =
                      (progress * 6 * 3.14159).clamp(-1.0, 1.0) * 10;
                  return Transform.translate(
                    offset: Offset(shake * (1 - progress), 0),
                    child: child,
                  );
                },
                child: TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 17,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceElevatedDark,
                    hintText: l10n.enterPassword,
                    errorText: _error,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 1.5),
                    ),
                    prefixIcon: const Icon(Icons.lock_outline,
                        size: 20, color: AppColors.textTertiaryDark),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.textTertiaryDark,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
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
                      : Text(l10n.unlock),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              TextButton(
                onPressed: widget.onCancel,
                child: Text(l10n.back,
                    style: const TextStyle(color: AppColors.textSecondaryDark)),
              ),

              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
