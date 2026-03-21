import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../security/key_management/key_manager.dart';
import '../../../services/firebase/firestore_service.dart';
import '../../../theme/app_colors.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _secretCodeController = TextEditingController();
  final _decoyCodeController = TextEditingController();
  final _deleteCodeController = TextEditingController();
  bool _isLoading = false;
  int _currentStep = 0;

  @override
  void dispose() {
    _secretCodeController.dispose();
    _decoyCodeController.dispose();
    _deleteCodeController.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    if (value.length < AppConstants.minCodeLength) {
      return 'Minimum ${AppConstants.minCodeLength} digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(value)) return 'Digits only';
    return null;
  }

  String? _validateUnique(String? value) {
    final base = _validateCode(value);
    if (base != null) return base;

    final codes = [
      _secretCodeController.text,
      _decoyCodeController.text,
      _deleteCodeController.text,
    ];
    final unique = codes.toSet();
    if (unique.length != codes.length && codes.where((c) => c == value).length > 1) {
      return 'Codes must be unique';
    }
    return null;
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final storage = context.read<SecureStorageService>();
      final auth = context.read<AuthService>();
      final keyManager = context.read<KeyManager>();
      final firestore = context.read<FirestoreService>();

      // 1. Create anonymous account
      final user = await auth.signInAnonymously();
      if (user == null) throw Exception('Authentication failed');

      // 2. Generate identity key pair
      final keyPair = await keyManager.getOrCreateIdentityKeyPair();

      // 3. Register public key on server
      await firestore.registerPublicKey(
        userId: user.uid,
        publicKeyBase64: keyPair.publicKeyBase64,
      );

      // 4. Store codes securely
      await Future.wait([
        storage.saveSecretCode(_secretCodeController.text),
        storage.saveDecoyCode(_decoyCodeController.text),
        storage.saveDeleteCode(_deleteCodeController.text),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Text(l10n.setupTitle, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  l10n.setupSubtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: _buildStepContent(l10n),
                ),
                _buildNavigation(l10n),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(AppLocalizations l10n) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_currentStep) {
        0 => _buildCodeInput(
            key: const ValueKey('secret'),
            label: l10n.secretCodeLabel,
            hint: l10n.secretCodeHint,
            controller: _secretCodeController,
            icon: Icons.lock_outline,
          ),
        1 => _buildCodeInput(
            key: const ValueKey('decoy'),
            label: l10n.decoyCodeLabel,
            hint: l10n.decoyCodeHint,
            controller: _decoyCodeController,
            icon: Icons.shield_outlined,
          ),
        2 => _buildCodeInput(
            key: const ValueKey('delete'),
            label: l10n.deleteCodeLabel,
            hint: l10n.deleteCodeHint,
            controller: _deleteCodeController,
            icon: Icons.delete_forever_outlined,
            isDestructive: true,
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildCodeInput({
    required Key key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool isDestructive = false,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? AppColors.destructive : AppColors.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(AppConstants.maxCodeLength),
          ],
          obscureText: true,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                letterSpacing: 8,
              ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          validator: _currentStep == 2 ? _validateUnique : _validateCode,
          autofocus: true,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            AppLocalizations.of(context)!.setupCodesInfo,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiaryDark,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildNavigation(AppLocalizations l10n) {
    return Row(
      children: [
        if (_currentStep > 0)
          TextButton(
            onPressed: () => setState(() => _currentStep--),
            child: const Text('Back'),
          ),
        const Spacer(),
        _buildStepIndicator(),
        const Spacer(),
        if (_currentStep < 2)
          ElevatedButton(
            onPressed: () {
              final controller = [
                _secretCodeController,
                _decoyCodeController,
                _deleteCodeController,
              ][_currentStep];
              if (_validateCode(controller.text) == null) {
                setState(() => _currentStep++);
              }
            },
            child: const Text('Next'),
          )
        else
          ElevatedButton(
            onPressed: _isLoading ? null : _completeSetup,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.setupContinue),
          ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          width: i == _currentStep ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: i == _currentStep ? AppColors.primary : AppColors.textTertiaryDark,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
